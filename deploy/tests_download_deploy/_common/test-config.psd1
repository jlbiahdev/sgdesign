# ============================================================
# CONFIGURATION DES TESTS DE download_deploy.ps1
# ============================================================
#
# Ce fichier est lu par TestHelpers.psm1 au début de chaque test.
# À adapter UNE FOIS à la machine de test, avant le premier jalon.
#
# Aucun secret dans ce fichier : les identifiants Artifactory restent
# dans les variables d'environnement ARTIFACTORY_USERNAME / ARTIFACTORY_TOKEN.
# ============================================================

@{
    # --------------------------------------------------------
    # Environnement FACTICE (jalons 0 à 9, et variantes « mode test »)
    # --------------------------------------------------------
    # Chaque scénario y crée son propre dossier :
    #   <RacineTestsAuto>\<nom du scénario>\{taskflow, api, HpcLite\...}
    # puis le supprime à la fin. Rien d'autre n'est jamais supprimé.
    # Doit être sur D: et ne contenir aucune donnée utile.
    RacineTestsAuto = "D:\Styx-Tests-Auto"

    # --------------------------------------------------------
    # Environnement RÉEL de test (jalons 9 à 18)
    # --------------------------------------------------------
    # Racine contenant les VRAIS binaires Styx :
    #   D:\Styx-Test\taskflow, \api, \HpcLite\{agent, runner, scheduler}
    # Les trois services Windows ci-dessous doivent exécuter les binaires
    # de CETTE racine (vérifié avant chaque test réel).
    RacineReelle = "D:\Styx-Test"

    # Racine de PRODUCTION. Sert uniquement :
    #   - de garde-fou : un test réel refuse de tourner si RacineReelle
    #     désigne la même racine ;
    #   - au jalon 19 (pré-vol -ValidationOnly et contrôles en lecture seule).
    RacineProduction = "D:\Applications"

    # Noms des services Windows de TEST. Ils doivent exécuter les binaires
    # de RacineReelle et être DIFFÉRENTS des services de production
    # (TaskFlow.Runner, HpcLite.Agent, HpcLite.Scheduler), qui pointent vers
    # RacineProduction. Les lanceurs injectent ces noms dans la copie testée
    # du script. _tools\New-FakeStyxTest.ps1 crée ces services.
    ServiceTaskflow  = "TaskFlow.Runner.Test"
    ServiceAgent     = "HpcLite.Agent.Test"
    ServiceScheduler = "HpcLite.Scheduler.Test"

    # Pool IIS de l'API sur la machine de test.
    PoolIis = "STYX"

    # Noms des exécutables (identiques au script de déploiement).
    ExecutableTaskflow  = "Socgen.TaskFlow.Runner.exe"
    ExecutableAgent     = "Styx.HpcLite.Agent.exe"
    ExecutableRunner    = "Styx.HpcLite.Runner.exe"
    ExecutableScheduler = "Styx.HpcLite.Scheduler.exe"

    # --------------------------------------------------------
    # Packages
    # --------------------------------------------------------
    # Vrai package Styx, téléchargé UNE FOIS à la main (voir README).
    # Utilisé par les jalons 15 à 18 : les lanceurs en font une copie
    # marquée (version.txt = nouvelle-version), jamais l'original.
    PackageReel = "D:\Styx-Test-Packages\Styx.Publish.nupkg"

    # URL Artifactory d'un vrai package (jalon 6 : téléchargements réels).
    # Laisser vide pour que les tests de téléchargement réel soient
    # signalés « non exécutés » (code 2) au lieu d'échouer.
    UrlPackageReel = ""
}
