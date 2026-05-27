# Usage examples

Interactive:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\Enable-SearchGleamEEA.ps1
```

Apply for Hungary:

```powershell
.\Enable-SearchGleamEEA.ps1 -Apply -Region HU -Force
```

Apply for all EEA-style region codes listed in the Windows region-policy file:

```powershell
.\Enable-SearchGleamEEA.ps1 -Apply -AllEEA -Force
```

Check status:

```powershell
.\Enable-SearchGleamEEA.ps1 -Status -Region HU
```

Revert:

```powershell
.\Enable-SearchGleamEEA.ps1 -Revert -Region HU
```

Restore backup:

```powershell
.\Enable-SearchGleamEEA.ps1 -RestoreFromBackup "C:\ProgramData\SearchGleamEEA\Backups\IntegratedServicesRegionPolicySet.json.20260527_120000.bak"
```
