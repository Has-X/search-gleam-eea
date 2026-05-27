# Search Gleam EEA

Bring back the cute Windows Search Highlights taskbar **gleam** on EEA/DMA-region Windows installs.

> The gleam is the small changing illustration/icon shown inside the Windows taskbar Search box.  
> This project is for people who want the tiny cute taskbar graphic back, not necessarily the whole “daily search slop” experience. 🦊

<p align="center">
  <img src="assets/taskbar.png" alt="Taskbar Search Gleam Example" />
</p>


## What this does

Windows 11 uses:

```text
C:\Windows\System32\IntegratedServicesRegionPolicySet.json
```

to region-gate integrated Windows services. On EEA installs, some Search/taskbar components can be disabled through this region-policy file. That can hide Search Highlights / the taskbar gleam, even when the ordinary user setting is missing or non-functional.

This script removes your selected region code, for example `HU`, from the `disabled` region lists of these policies:

| Policy | GUID |
|---|---|
| First party Taskbar Gleam customization is shown | `{61bf5046-c5db-4cd3-b6bf-929e5b421a6a}` |
| SearchV2 on Taskbar feature | `{983e7839-8ee8-4705-81f0-962b8966b7d7}` |
| Manage Vega search in Windows Search Box | `{b1a7c9e2-3d4f-4a6b-8c9d-1a2b3c4d5e6f}` |

It also enables the normal per-user Search Highlights/taskbar search registry defaults.

## What this does not do

- It does **not** bypass Windows activation, licensing, authentication, or DRM.
- It does **not** install malware, inject code, patch binaries, or disable security products.
- It does **not** remove Microsoft Edge, Bing, Widgets, Copilot, or ads.
- It does **not** guarantee Microsoft server-side Search Highlights content will be available forever.
- It does **not** make this a supported Microsoft configuration.

## Big warning

This is an unsupported Windows tweak.

Windows Update may overwrite `IntegratedServicesRegionPolicySet.json`. If the gleam disappears after an update, run the status command and apply again if needed.

This may affect Windows behavior Microsoft intentionally region-gated for EEA/DMA compliance. Use it only on systems you own or administer and only if you understand the tradeoff.

## Requirements

- Windows 11
- PowerShell 5.1 or PowerShell 7+
- Administrator rights
- Taskbar Search set to **Search box** mode, not hidden/icon-only

## Quick start

Download or clone the repo, then run PowerShell:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\Enable-SearchGleamEEA.ps1
```

The script is interactive by default. It will:

1. detect a default region code,
2. ask what to do,
3. self-elevate if needed,
4. create a backup,
5. patch the target policy gates,
6. enable the relevant HKCU Search settings,
7. replace the protected JSON directly or schedule a boot-time replacement,
8. ask for reboot if needed.

## Non-interactive apply

Example for Hungary:

```powershell
.\Enable-SearchGleamEEA.ps1 -Apply -Region HU -Force
```

Patch all EEA-style region codes from the target disabled lists:

```powershell
.\Enable-SearchGleamEEA.ps1 -Apply -AllEEA -Force
```

Dry run:

```powershell
.\Enable-SearchGleamEEA.ps1 -Apply -Region HU -DryRun
```

## Check status

```powershell
.\Enable-SearchGleamEEA.ps1 -Status -Region HU
```

Good status looks like this for the three target policies:

```text
DisabledForRegion : False
```

## Revert

To add your region back to the disabled lists for the three target policies:

```powershell
.\Enable-SearchGleamEEA.ps1 -Revert -Region HU
```

This reverts the region-policy part for the three target gates. It does not restore every other file formatting/detail from a backup.

## Restore from backup

Backups are stored in:

```text
C:\ProgramData\SearchGleamEEA\Backups
```

Restore a specific backup:

```powershell
.\Enable-SearchGleamEEA.ps1 -RestoreFromBackup "C:\ProgramData\SearchGleamEEA\Backups\IntegratedServicesRegionPolicySet.json.20260527_120000.bak"
```

## If the file is locked

That is normal.

The script first tries to replace the JSON directly. If Windows has the file locked, it schedules a boot-time replacement through:

```text
HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\PendingFileRenameOperations
```

Then reboot. After reboot, run status again.

## If the toggle appears but no gleam shows

Try:

```powershell
Stop-Process -Name SearchHost -Force -ErrorAction SilentlyContinue
Stop-Process -Name StartMenuExperienceHost -Force -ErrorAction SilentlyContinue
Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
Restart-Service WSearch -Force -ErrorAction SilentlyContinue
Start-Process explorer.exe
```

Then go to:

```text
Settings → Privacy & security → Search permissions → Show search highlights
```

Toggle it off, wait a few seconds, then turn it on again.

Search Highlights content may also depend on Microsoft’s server-side availability and rollout state.

## Known policy blockers

The script reports these known blockers in status mode:

| Registry value | Blocking value |
|---|---:|
| `HKCU\Software\Policies\Microsoft\Windows\Explorer\DisableSearchBoxSuggestions` | `1` |
| `HKLM\Software\Policies\Microsoft\Windows\Explorer\DisableSearchBoxSuggestions` | `1` |
| `HKCU\Software\Policies\Microsoft\Windows\Windows Search\AllowSearchHighlights` | `0` |
| `HKLM\Software\Policies\Microsoft\Windows\Windows Search\AllowSearchHighlights` | `0` |

To remove known blocking policy values, run with:

```powershell
.\Enable-SearchGleamEEA.ps1 -Apply -Region HU -FixPolicyBlockers
```

Do not use this on managed corporate/school devices unless you are allowed to override policy settings.

## Why is this so locked down?

The short version: EEA/DMA compliance.

Microsoft region-gated a lot of integrated Windows behavior around Search, Edge, Widgets, taskbar integrations, default apps, and related services. The cute gleam appears to depend on Search/taskbar infrastructure that gets disabled in EEA regions. This tool flips only the observed Search/Gleam gates for your selected region.

## Troubleshooting checklist

1. Run status:
   ```powershell
   .\Enable-SearchGleamEEA.ps1 -Status -Region HU
   ```
2. Confirm all three target policies show `DisabledForRegion : False`.
3. Confirm the taskbar Search mode is **Search box**.
4. Confirm Search Highlights is enabled in Settings.
5. Restart Search/Explorer.
6. Reboot once.
7. If a Windows update reverted the JSON, apply again.

## Safety notes

- Backups are created before changing the policy file.
- Local Administrators are referenced by well-known SID `S-1-5-32-544`, so the script works on localized Windows installs.
- The script validates staged JSON before installing it.
- If direct replacement fails, it uses boot-time replacement rather than repeatedly fighting the file lock.
- The script is intentionally GUID-based, not fragile comment-text-based.

## License

MIT. See [`LICENSE`](LICENSE).
