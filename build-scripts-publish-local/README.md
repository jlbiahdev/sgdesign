# Publication locale Styx

Publie les applications Styx en self-contained (`win-x64`) dans un dossier local, avec la même arborescence que les serveurs.

| Script | Rôle | Appelle |
|---|---|---|
| `publish-local-styx.ps1` | Sans paramètre : publie dans `C:\Styx` | `publish-local.ps1` |
| `publish-local.ps1` | Publie les 5 applications dans `-Destination` | `build.ps1` avec `-Build` |
| `build.ps1` | Restore, clean et rebuild de toute la solution | — |
| `StyxBuild.psm1` | Configuration commune (chemins, projets, options .NET) et fonctions partagées | — |

Les scripts se placent dans `01_POC\src\scripts\devops\server\`. La racine du dépôt est trouvée par Git à partir de ce dossier.

Tous les scripts sortent avec le code `0` en cas de succès et `1` en cas d'erreur.

---

## Utilisation

```powershell
.\publish-local-styx.ps1                          # dans C:\Styx
.\publish-local.ps1 -Destination D:\AutreDossier   # dans un autre dossier
.\publish-local.ps1 -Destination C:\Styx -Build    # en recompilant d'abord toute la solution
```

| Paramètre de `publish-local.ps1` | Effet |
|---|---|
| `-Destination <dossier>` | **Obligatoire.** Racine locale, créée si besoin. La racine d'un lecteur est refusée |
| `-Build` | Lance d'abord `build.ps1` (clean et rebuild de toute la solution) |

Arborescence produite :

```
<Destination>\
├── api\
├── taskflow\
└── HpcLite\{agent, runner, scheduler}\
```

## Comportement

- **Refus** si une application tourne depuis un de ces dossiers (exe verrouillé) : la liste des processus est affichée et rien n'est modifié. Le contrôle est refait juste avant l'installation.
- Toutes les applications sont d'abord publiées dans un dossier de travail (`%TEMP%\styx_build\<date>-<id>`). Les dossiers cibles ne sont touchés que si **toutes** les publications ont réussi : une erreur ne laisse jamais un dossier vide ou à moitié rempli.
- Chaque dossier cible est **vidé puis remplacé**, configuration comprise (`appsettings*.json`, `web.config`…).
- Le dossier de travail est supprimé en cas de succès et conservé en cas d'erreur, pour le diagnostic.

## Configuration

Dans `StyxBuild.psm1`, section `>>> DEBUT CONFIGURATION` : chemins de la solution, liste des projets avec leur sous-dossier, runtime, options de restore et de build.
