# Security

## Reporting a vulnerability

Please do not open a public issue. Use **Security > Report a vulnerability** on this repository, which sends a private report to the maintainer. Describe what you found and how to reproduce it. You will get an answer within 7 days.

## How YSO protects your PC

- **Administrator rights, asked once.** YSO needs them to clean system folders and install updates. It asks through the normal Windows prompt (UAC).
- **Its settings can only be changed by administrators.** YSO runs with administrator rights and reads its settings from `C:\ProgramData\YSO`, so standard users may read that folder but not change it. Scheduled tasks run a copy of YSO in `C:\Program Files\YSO`, which standard users cannot change either.
- **Verified updates.** New versions are published as GitHub Releases by the test pipeline, only after every test has passed, with a SHA-256 file. YSO downloads them over HTTPS from GitHub only, and installs one only if its checksum matches, PowerShell reads it without errors, and its version is the one announced. Otherwise YSO stays as it was.
- **Checked input.** Settings files, numbers, folder paths, app identifiers and data read from GitHub or winget are checked before use. App identifiers are never passed to winget unless they look like one.
- **Nothing secret in this repository.** YSO uses no API key or password. A test fails if a token, private key or password appears in the files.
- **Pinned dependencies.** YSO uses only what Windows includes. The GitHub Actions used by the tests are pinned to a commit, Dependabot proposes their updates, and the workflow has read-only access except for the jobs that publish.
