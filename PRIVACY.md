# Privacy policy

Last updated: October 25, 2026. Version française plus bas.

YSO (Your System Optimizer) is a free, open-source program that runs only on your own PC. It is maintained by [b-draoui](https://github.com/b-draoui) as a personal project, not by a company.

## What we receive from you

Nothing. YSO has no account, no telemetry, no analytics, no advertising and no cookies. It never sends your files, your settings or anything about your PC to us or to anyone else.

## What YSO keeps on your PC

In `C:\ProgramData\YSO`, readable by the users of the PC and changeable by administrators only:

| File | What it contains | How long |
|---|---|---|
| `settings.json` | Your choices (language, what weekly cleaning does, folders never to touch...) | Until you change or delete them |
| `history.csv`, `updates.csv` | Date, type and size of each cleanup; apps and drivers updated | Until you delete them |
| `Logs\` | What YSO showed during each session, which can include file paths and your Windows user name | The 30 newest sessions |
| `errors.log`, `Reports\` | Details of errors and self-test results, to fix problems | `errors.log` is renamed once it reaches 1 MB |
| `yso-version-check.json` | The last answer of GitHub about new versions of YSO | Replaced at each check |

## Network connections made by YSO

YSO connects to the internet only for these features. Each connection goes from your PC to the service named, and that service sees your IP address, as with any website.

- **New versions of YSO**: when the window opens, at most once an hour, YSO asks GitHub (`api.github.com`) for the latest release. GitHub also receives the YSO version number. You can turn this off in Settings. When you click **Update**, the new version is downloaded from GitHub. See [GitHub's privacy statement](https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement).
- **App and driver updates (28)**: winget (Microsoft) and Windows Update, only when you use this option or turn on scheduled updates. App installers are downloaded from their publishers through winget.
- **Network check (11)**: pings your router, `1.1.1.1` (Cloudflare) and `8.8.8.8` (Google), and looks up three website names to time DNS servers.
- **Installation** (`install.ps1`): downloads YSO from GitHub.

## Problem reports

**Report a problem (P)** creates a zip file on your Desktop. User names, the PC name, private IP addresses and the Wi-Fi name are removed first. Nothing is sent: you decide whether to attach it to a GitHub issue. Anything you post on GitHub is public and covered by GitHub's terms.

## Children

YSO collects no personal data from anyone, children included.

## Deleting your data

Everything YSO keeps is on your PC. To delete it, uninstall YSO (Settings > Apps > Installed apps > YSO) and answer **No** when it asks to keep the history and settings, or delete the folder `C:\ProgramData\YSO`. We hold no copy, so there is nothing else to request. To remove something you posted in a GitHub issue, edit or delete it on GitHub.

## Changes

Changes to this policy are made in this file; its history on GitHub shows every version.

## Contact

Open an [issue on GitHub](https://github.com/b-draoui/yso/issues). For security problems, see [SECURITY.md](SECURITY.md).

---

## Politique de confidentialité (français)

YSO est un programme gratuit et open source qui fonctionne uniquement sur votre PC. Il est maintenu par [b-draoui](https://github.com/b-draoui) à titre personnel, pas par une entreprise.

- **Ce que nous recevons** : rien. Pas de compte, pas de télémétrie, pas de statistiques, pas de publicité, pas de cookies.
- **Ce que YSO garde sur votre PC**, dans `C:\ProgramData\YSO` (lisible par les utilisateurs du PC, modifiable seulement par les administrateurs) : les réglages, l'historique des nettoyages et des mises à jour, les journaux des 30 dernières sessions (qui peuvent contenir des chemins de fichiers et votre nom d'utilisateur Windows), les erreurs et les résultats de l'autotest.
- **Connexions réseau** : vérification des nouvelles versions de YSO sur GitHub à l'ouverture de la fenêtre, au plus une fois par heure (désactivable dans les Paramètres) ; téléchargement de la mise à jour quand vous cliquez sur **Mettre à jour** ; winget et Windows Update pour l'option 28 ; test réseau (option 11) vers votre box, 1.1.1.1 et 8.8.8.8 ; installation depuis GitHub. Chaque service contacté voit votre adresse IP, comme n'importe quel site web.
- **Signaler un problème (P)** crée un zip sur votre Bureau, sans noms d'utilisateur, nom du PC, adresses IP privées ni nom du Wi-Fi. Rien n'est envoyé automatiquement.
- **Supprimer vos données** : désinstallez YSO et répondez **Non** quand il propose de garder l'historique et les réglages, ou supprimez le dossier `C:\ProgramData\YSO`. Nous n'en avons aucune copie.
- **Contact** : une [issue sur GitHub](https://github.com/b-draoui/yso/issues).
