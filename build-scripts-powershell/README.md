# Scripts de build Styx

Remplacent `check-before-push.bat`, `check-and-push.bat`, `publish-styx-full.bat` et `push-styx-artifactory-token.bat`.

| Script | Rôle | Appelle |
|---|---|---|
| `build.ps1` | Restore, clean et rebuild de toute la solution (plus tard : tests unitaires) | — |
| `push-git.ps1` | Vérifie que le dépôt est propre, compile, puis `git push`. **Bouton Visual Studio** | `build.ps1` |
| `package.ps1` | Compile, publie les 5 applications, crée `Styx.Publish.<version>.nupkg` | `build.ps1`, et `push-artifactory.ps1` avec `-Push` |
| `push-artifactory.ps1` | Pousse **un** `.nupkg` donné vers Artifactory | — |
| `StyxBuild.psm1` | Configuration commune et fonctions partagées | — |

Toute la configuration (chemins, projets, options .NET, share, Artifactory) est dans `StyxBuild.psm1`, section `>>> DEBUT CONFIGURATION`.

Tous les scripts sortent avec le code `0` en cas de succès et `1` en cas d'erreur.

---

## Utilisation

```powershell
.\build.ps1                       # compiler
.\push-git.ps1                    # compiler puis pousser le code
.\package.ps1                     # compiler et produire le .nupkg
.\package.ps1 -Push               # ... et le pousser vers Artifactory
.\push-artifactory.ps1 -PackageFile "<chemin du .nupkg>"
```

### `push-git.ps1`

| Paramètre | Effet |
|---|---|
| `-SkipBuild` | Pousse sans compiler |

Le script **refuse** de pousser si :
- le dossier de travail contient des modifications non commitées, car le build doit porter exactement sur ce qui est poussé : commiter, ou `git stash -u` ;
- la branche n'a pas de branche distante : faire le premier push à la main avec `git push -u origin <branche>`.

S'il n'y a aucun commit à pousser, il s'arrête sans compiler (code 0).

### `package.ps1`

| Paramètre | Effet |
|---|---|
| `-SkipBuild` | Ne lance pas `build.ps1` |
| `-Push` | Pousse vers Artifactory le package qui vient d'être créé |
| `-SyncShare` | Copie aussi les applications, `start_all.ps1` et `env.ps1` sur le share réseau (en miroir) |
| `-PackageVersion <v>` | Version imposée. Par défaut : `1.<AAMMJJ>.<HHMMSS>` |
| `-PackageId <id>` | Par défaut : `Styx.Publish` |
| `-OutputDirectory <dossier>` | Où déposer le `.nupkg`. Par défaut : `%TEMP%\styx_packages` |
| `-KeepWorkDirectory` | Conserve le dossier de travail (publication, zip) |

Contenu du package (attendu par `download_deploy.ps1`) :

```
Styx.Publish.<version>.nupkg
└── content\styx_publish.zip
    ├── api\
    ├── hpclite\{agent, runner, scheduler}\
    └── taskflow\
```

Chaque exécution travaille dans son propre dossier `%TEMP%\styx_build\<date>-<id>`. Ce dossier est supprimé en cas de succès et conservé en cas d'erreur, pour le diagnostic.

### `push-artifactory.ps1`

- Le `.nupkg` est **obligatoire** (`-PackageFile`) : le script ne pousse jamais « le dernier trouvé ».
- La clé d'API est lue dans la variable d'environnement `ARTIFACTORY_API_KEY` (session, utilisateur ou machine). Elle n'est jamais dans un fichier.
- Une version déjà présente sur Artifactory est une **erreur** : relancer `package.ps1` pour produire une nouvelle version.

```powershell
# Une fois pour toutes (utilisateur) :
[Environment]::SetEnvironmentVariable("ARTIFACTORY_API_KEY", "<clé>", "User")
```

---

## Bouton Visual Studio

*Outils > Outils externes*, entrée **STYX [POC] - Build + Push** :

| Champ | Valeur |
|---|---|
| Command | `C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe` |
| Arguments | `-NoProfile -ExecutionPolicy Bypass -File "$(SolutionDir)..\scripts\devops\server\push-git.ps1"` |
| Initial directory | `$(SolutionDir)` |
| Use Output window | coché |

Si les accents s'affichent mal dans la fenêtre Output, inverser la case *Treat output as Unicode*.

---

## Changements par rapport aux `.bat`

- Plus de frontend (`npm`, dossier `app\`).
- Taskflow est contrôlé et compilé comme les autres projets.
- Zip conforme : séparateurs `/` au lieu de `\` (`download_deploy.ps1` accepte les deux).
- Share réseau optionnel (`-SyncShare`).
- Push Git refusé si le dossier de travail n'est pas propre.
- Push Artifactory : fichier explicite, clé d'API hors du script, pas de `--skip-duplicate`.
- Dossiers de travail uniques par exécution.
