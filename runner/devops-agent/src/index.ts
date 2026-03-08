#!/usr/bin/env node
/**
 * DevOps Agent
 * Un agent Claude qui analyse un projet et configure automatiquement
 * l'environnement Docker (docker-compose.yml + scripts de démarrage).
 *
 * Usage :
 *   ANTHROPIC_API_KEY=sk-... npx tsx src/index.ts --project /chemin/vers/projet
 */

import Anthropic from '@anthropic-ai/sdk'
import fs from 'fs'
import path from 'path'
import { execSync } from 'child_process'

// ---------------------------------------------------------------------------
// Chargement .env (cherche dans le dossier de l'agent, puis HOME)
// ---------------------------------------------------------------------------
function loadEnv() {
  const candidates = [
    path.join(path.dirname(new URL(import.meta.url).pathname), '..', '.env'),
    path.join(process.env.HOME ?? '~', '.devops-agent.env'),
  ]
  for (const envFile of candidates) {
    if (fs.existsSync(envFile)) {
      const lines = fs.readFileSync(envFile, 'utf-8').split('\n')
      for (const line of lines) {
        const trimmed = line.trim()
        if (!trimmed || trimmed.startsWith('#')) continue
        const [key, ...rest] = trimmed.split('=')
        if (key && !process.env[key]) {
          process.env[key] = rest.join('=').replace(/^["']|["']$/g, '')
        }
      }
      break
    }
  }
}
loadEnv()

if (!process.env.ANTHROPIC_API_KEY || process.env.ANTHROPIC_API_KEY.includes('REMPLACER')) {
  console.error('\n❌ ANTHROPIC_API_KEY non configurée.')
  console.error('   1. Va sur https://console.anthropic.com/settings/keys')
  console.error('   2. Crée une clé et copie-la')
  console.error('   3. Ajoute-la dans ~/.zshrc :')
  console.error('      export ANTHROPIC_API_KEY="sk-ant-..."')
  console.error('   Ou crée ~/.devops-agent.env :')
  console.error('      ANTHROPIC_API_KEY=sk-ant-...\n')
  process.exit(1)
}

// ---------------------------------------------------------------------------
// CLI
// ---------------------------------------------------------------------------
const args = process.argv.slice(2)
const projectArg = args.indexOf('--project')
const projectPath = projectArg >= 0
  ? path.resolve(args[projectArg + 1])
  : process.cwd()

if (!fs.existsSync(projectPath)) {
  console.error(`Dossier introuvable : ${projectPath}`)
  process.exit(1)
}

console.log(`\n🤖 DevOps Agent — analyse de : ${projectPath}\n`)

// ---------------------------------------------------------------------------
// Outils disponibles pour l'agent
// ---------------------------------------------------------------------------
const tools: Anthropic.Tool[] = [
  {
    name: 'read_file',
    description: 'Lit le contenu d\'un fichier du projet.',
    input_schema: {
      type: 'object',
      properties: {
        relative_path: { type: 'string', description: 'Chemin relatif depuis la racine du projet' }
      },
      required: ['relative_path']
    }
  },
  {
    name: 'list_files',
    description: 'Liste les fichiers d\'un dossier du projet.',
    input_schema: {
      type: 'object',
      properties: {
        relative_path: { type: 'string', description: 'Chemin relatif (ex: "." pour la racine)' },
        depth: { type: 'number', description: 'Profondeur max (défaut: 2)' }
      },
      required: ['relative_path']
    }
  },
  {
    name: 'write_file',
    description: 'Crée ou écrase un fichier dans le projet.',
    input_schema: {
      type: 'object',
      properties: {
        relative_path: { type: 'string' },
        content: { type: 'string' }
      },
      required: ['relative_path', 'content']
    }
  },
  {
    name: 'run_command',
    description: 'Exécute une commande shell dans le dossier du projet. Uniquement docker, dotnet, npm, node.',
    input_schema: {
      type: 'object',
      properties: {
        command: { type: 'string', description: 'Commande à exécuter' }
      },
      required: ['command']
    }
  },
  {
    name: 'check_tool_installed',
    description: 'Vérifie si un outil CLI est installé sur la machine.',
    input_schema: {
      type: 'object',
      properties: {
        tool: { type: 'string', description: 'Nom de l\'outil (ex: docker, dotnet, node)' }
      },
      required: ['tool']
    }
  }
]

// ---------------------------------------------------------------------------
// Exécution des outils
// ---------------------------------------------------------------------------
function executeTool(name: string, input: Record<string, unknown>): string {
  const ALLOWED_COMMANDS = ['docker', 'dotnet', 'npm', 'node', 'brew']

  switch (name) {
    case 'read_file': {
      const filePath = path.join(projectPath, input.relative_path as string)
      if (!fs.existsSync(filePath)) return `Fichier non trouvé : ${filePath}`
      return fs.readFileSync(filePath, 'utf-8').slice(0, 8000) // limite contexte
    }

    case 'list_files': {
      const dirPath = path.join(projectPath, input.relative_path as string)
      const depth = (input.depth as number) ?? 2
      try {
        const result = execSync(
          `find "${dirPath}" -maxdepth ${depth} -not -path "*/node_modules/*" -not -path "*/.git/*" -not -path "*/bin/*" -not -path "*/obj/*"`,
          { encoding: 'utf-8' }
        )
        return result
      } catch {
        return 'Erreur lors de la liste des fichiers'
      }
    }

    case 'write_file': {
      const filePath = path.join(projectPath, input.relative_path as string)
      fs.mkdirSync(path.dirname(filePath), { recursive: true })
      fs.writeFileSync(filePath, input.content as string, 'utf-8')
      console.log(`  ✓ Fichier écrit : ${input.relative_path}`)
      return `Fichier créé : ${input.relative_path}`
    }

    case 'run_command': {
      const cmd = input.command as string
      const firstWord = cmd.trim().split(' ')[0]
      if (!ALLOWED_COMMANDS.includes(firstWord)) {
        return `Commande refusée pour sécurité : '${firstWord}'. Autorisées : ${ALLOWED_COMMANDS.join(', ')}`
      }
      try {
        console.log(`  $ ${cmd}`)
        const result = execSync(cmd, { cwd: projectPath, encoding: 'utf-8', timeout: 60_000 })
        return result || '(succès, pas de sortie)'
      } catch (e: unknown) {
        return `Erreur : ${(e as Error).message}`
      }
    }

    case 'check_tool_installed': {
      const tool = input.tool as string
      try {
        execSync(`which ${tool}`, { stdio: 'pipe' })
        const version = execSync(`${tool} --version 2>&1 || true`, { encoding: 'utf-8' }).trim().split('\n')[0]
        return `${tool} est installé : ${version}`
      } catch {
        return `${tool} n'est PAS installé`
      }
    }

    default:
      return `Outil inconnu : ${name}`
  }
}

// ---------------------------------------------------------------------------
// Agent loop
// ---------------------------------------------------------------------------
async function runAgent() {
  const client = new Anthropic()

  const systemPrompt = `Tu es un agent DevOps expert. Ton rôle est d'analyser un projet et de configurer automatiquement son environnement de développement Docker.

Tu dois :
1. Lister et analyser les fichiers du projet (package.json, *.csproj, *.sln, appsettings.json, etc.)
2. Détecter les dépendances infrastructure (PostgreSQL, Redis, MongoDB, RabbitMQ, etc.)
3. Vérifier les outils installés sur la machine (docker, dotnet, node)
4. Générer un docker-compose.yml adapté au projet
5. Générer un script dev-start.sh pour lancer l'environnement
6. Démarrer PostgreSQL et vérifier qu'il est prêt
7. Appliquer les migrations SQL si un dossier migrations/ existe
8. Afficher un résumé clair de ce qui a été fait et comment démarrer

Règles :
- N'exécute que des commandes docker, dotnet, npm, node
- Si docker n'est pas installé, explique comment l'installer
- Adapte toujours la configuration au projet analysé (ports, db name, etc.)
- Génère des fichiers propres et commentés`

  const messages: Anthropic.MessageParam[] = [
    {
      role: 'user',
      content: `Analyse le projet dans le dossier courant et configure l'environnement Docker. Le projet est : ${projectPath}`
    }
  ]

  let iteration = 0
  const MAX_ITERATIONS = 20

  while (iteration < MAX_ITERATIONS) {
    iteration++

    const response = await client.messages.create({
      model: 'claude-opus-4-6',
      max_tokens: 4096,
      system: systemPrompt,
      tools,
      messages
    })

    // Afficher le texte de l'agent
    for (const block of response.content) {
      if (block.type === 'text' && block.text.trim()) {
        console.log('\n' + block.text)
      }
    }

    if (response.stop_reason === 'end_turn') break

    if (response.stop_reason === 'tool_use') {
      const toolResults: Anthropic.ToolResultBlockParam[] = []

      for (const block of response.content) {
        if (block.type === 'tool_use') {
          console.log(`\n🔧 ${block.name}(${JSON.stringify(block.input).slice(0, 80)}…)`)
          const result = executeTool(block.name, block.input as Record<string, unknown>)
          toolResults.push({
            type: 'tool_result',
            tool_use_id: block.id,
            content: result
          })
        }
      }

      messages.push({ role: 'assistant', content: response.content })
      messages.push({ role: 'user', content: toolResults })
    }
  }

  console.log('\n✅ Agent terminé.\n')
}

runAgent().catch((e) => {
  console.error('Erreur fatale :', e.message)
  process.exit(1)
})
