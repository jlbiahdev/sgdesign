# ======================================================================
# Variables d'environnement utilisées par download_deploy.ps1
# ======================================================================
#
# Le script de déploiement a besoin de trois informations :
#   - ARTIFACTORY_USERNAME : le compte qui se connecte à Artifactory
#   - ARTIFACTORY_TOKEN    : le jeton (mot de passe) de ce compte
#   - STYX_PACKAGE_URL     : l'adresse complète du package à déployer
#
# Elles sont stockées dans des variables d'environnement pour qu'aucun
# secret ne soit jamais écrit dans un script.
#
# Deux façons de les définir : OPTION 1 ou OPTION 2 ci-dessous.
# Remplacer les valeurs entre guillemets ("usr-cd-...", etc.) par les
# vraies valeurs avant d'exécuter.


# ----------------------------------------------------------------------
# OPTION 1 : définition PERMANENTE, pour tout le serveur (niveau Machine)
# ----------------------------------------------------------------------
# - À lancer dans une console PowerShell ouverte « en tant
#   qu'administrateur » (sinon Windows refuse l'écriture).
# - Les valeurs restent enregistrées, même après un redémarrage.
# - Les consoles déjà ouvertes ne voient pas les nouvelles valeurs dans
#   $env:. Sans effet sur download_deploy.ps1, qui les relit directement
#   au niveau Machine.
# - ATTENTION : toute personne qui se connecte au serveur peut lire ces
#   valeurs, token compris.

# Compte Artifactory (commence généralement par « usr-cd- »).
[Environment]::SetEnvironmentVariable("ARTIFACTORY_USERNAME", "usr-cd-...", "Machine")

# Jeton du compte : c'est un secret, ne jamais le copier ailleurs.
[Environment]::SetEnvironmentVariable("ARTIFACTORY_TOKEN",    "eyJ2...",    "Machine")

# Adresse complète du package .nupkg à déployer (doit commencer par https://).
[Environment]::SetEnvironmentVariable("STYX_PACKAGE_URL",     "https://.../Styx.Publish.1.260807.162806.nupkg", "Machine")


# ----------------------------------------------------------------------
# OPTION 2 : définition TEMPORAIRE, pour cette console uniquement
# ----------------------------------------------------------------------
# - Les valeurs disparaissent à la fermeture de la console.
# - Plus prudent pour le token si d'autres personnes utilisent le serveur.
# - Lancer download_deploy.ps1 depuis cette MÊME console.
# - Si une variable existe aussi au niveau Machine, c'est la valeur
#   définie ici qui est utilisée.

$env:ARTIFACTORY_USERNAME = "usr-cd-..."      # compte Artifactory
$env:ARTIFACTORY_TOKEN    = "eyJ2..."         # jeton (secret)
$env:STYX_PACKAGE_URL     = "https://.../Styx.Publish.1.260807.162806.nupkg"   # adresse du package


# ----------------------------------------------------------------------
# VÉRIFICATION : les variables sont-elles bien définies ?
# ----------------------------------------------------------------------
# Affiche, pour chaque variable, si elle est présente dans la console
# (session) et au niveau Machine : True = présente, False = absente.
# Les valeurs elles-mêmes ne sont jamais affichées : le token reste secret.

foreach ($n in "ARTIFACTORY_USERNAME", "ARTIFACTORY_TOKEN", "STYX_PACKAGE_URL") {
    "{0,-22} session : {1,-5} machine : {2}" -f $n,
        (-not [string]::IsNullOrEmpty([Environment]::GetEnvironmentVariable($n, "Process"))),
        (-not [string]::IsNullOrEmpty([Environment]::GetEnvironmentVariable($n, "Machine")))
}