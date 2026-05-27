# Security policy

This project changes a protected Windows system JSON file and HKCU Search settings.

Please do not run random scripts from the internet blindly. Read the script first, keep backups, and use it only on systems you own or administer.

## Reporting issues

Open a GitHub issue with:

- Windows version/build
- PowerShell version
- region code used
- output of `./Enable-SearchGleamEEA.ps1 -Status -Region XX`
- whether the change was direct or scheduled for reboot

Do not include private account names, machine names, or sensitive policy data unless you have redacted it.
