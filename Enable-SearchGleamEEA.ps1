<# 
.SYNOPSIS
  Re-enable the Windows Search Highlights taskbar "gleam" on EEA/DMA-region Windows installs.

.DESCRIPTION
  Windows 11 uses IntegratedServicesRegionPolicySet.json to region-gate certain integrated
  services. On EEA installs, the Search Highlights taskbar gleam may be hidden even when the
  user-facing "Show search highlights" toggle exists.

  This script removes a selected region code (for example HU) from the "disabled" lists of
  the three Search/Gleam policies that were observed to control the feature:

    - First party Taskbar Gleam customization is shown
    - SearchV2 on Taskbar feature
    - Manage Vega search in Windows Search Box

  It creates backups, uses language-independent Administrators SID permissions, supports
  boot-time replacement if the system JSON is locked, and can show status/revert changes.

.NOTES
  This is an unsupported Windows tweak. Windows Update may overwrite the file.
  Use at your own risk. Keep backups.

.EXAMPLE
  .\Enable-SearchGleamEEA.ps1

.EXAMPLE
  .\Enable-SearchGleamEEA.ps1 -Apply -Region HU

.EXAMPLE
  .\Enable-SearchGleamEEA.ps1 -Status -Region HU

.EXAMPLE
  .\Enable-SearchGleamEEA.ps1 -Revert -Region HU

.EXAMPLE
  .\Enable-SearchGleamEEA.ps1 -RestoreFromBackup "C:\ProgramData\SearchGleamEEA\Backups\IntegratedServicesRegionPolicySet.json.20260527_120000.bak"
#>

[CmdletBinding(DefaultParameterSetName = "Interactive")]
param(
    [Parameter(ParameterSetName = "Apply")]
    [switch] $Apply,

    [Parameter(ParameterSetName = "Revert")]
    [switch] $Revert,

    [Parameter(ParameterSetName = "Restore")]
    [string] $RestoreFromBackup,

    [Parameter(ParameterSetName = "Status")]
    [switch] $Status,

    [ValidatePattern("^[A-Za-z]{2}$")]
    [string] $Region,

    [string] $PolicyFile = "$env:WINDIR\System32\IntegratedServicesRegionPolicySet.json",

    [switch] $AllEEA,

    [switch] $DryRun,

    [switch] $Force,

    [switch] $NoAutoElevate,

    [switch] $NoRebootPrompt,

    [switch] $FixPolicyBlockers,

    [switch] $SkipRegistryTweaks
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

$AppName = "SearchGleamEEA"
$RootDir = Join-Path $env:ProgramData $AppName
$BackupDir = Join-Path $RootDir "Backups"
$StagingDir = Join-Path $RootDir "Staging"
$LogDir = Join-Path $RootDir "Logs"

$TargetPolicies = @(
    [pscustomobject]@{
        Name = "First party Taskbar Gleam customization is shown"
        Guid = "{61bf5046-c5db-4cd3-b6bf-929e5b421a6a}"
        Why  = "Allows Microsoft's own taskbar Search Highlights gleam."
    },
    [pscustomobject]@{
        Name = "SearchV2 on Taskbar feature"
        Guid = "{983e7839-8ee8-4705-81f0-962b8966b7d7}"
        Why  = "Allows the newer taskbar search implementation used by the gleam."
    },
    [pscustomobject]@{
        Name = "Manage Vega search in Windows Search Box"
        Guid = "{b1a7c9e2-3d4f-4a6b-8c9d-1a2b3c4d5e6f}"
        Why  = "Allows the Windows Search Box path that can render the gleam."
    }
)

$EEARegionCodes = @(
    "AT","BE","BG","CH","CY","CZ","DE","DK","EE","ES","FI","FR","GF","GP","GR","HR",
    "HU","IE","IS","IT","LI","LT","LU","LV","MT","MQ","NL","NO","PL","PT","RE","RO",
    "SE","SI","SK","YT"
)

function Write-Info {
    param([string] $Message)
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

function Write-Ok {
    param([string] $Message)
    Write-Host "[ OK ] $Message" -ForegroundColor Green
}

function Write-Warn {
    param([string] $Message)
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Write-Fail {
    param([string] $Message)
    Write-Host "[FAIL] $Message" -ForegroundColor Red
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function ConvertTo-CommandLineArgument {
    param([object] $Value)

    if ($null -eq $Value) { return '""' }

    $text = [string] $Value
    if ($text -match '[\s"`]') {
        return '"' + ($text -replace '"', '\"') + '"'
    }

    return $text
}

function Invoke-SelfElevationIfNeeded {
    if ($NoAutoElevate) { return }

    $needsAdmin = -not $Status
    if (-not $needsAdmin) { return }

    if (Test-IsAdministrator) { return }

    if (-not $PSCommandPath) {
        throw "Cannot self-elevate because PSCommandPath is empty. Save the script to disk and run it again."
    }

    $exe = (Get-Process -Id $PID).Path
    $argList = New-Object System.Collections.Generic.List[string]
    $argList.Add("-NoProfile")
    $argList.Add("-ExecutionPolicy")
    $argList.Add("Bypass")
    $argList.Add("-File")
    $argList.Add((ConvertTo-CommandLineArgument $PSCommandPath))

    foreach ($key in $PSBoundParameters.Keys) {
        if ($key -eq "NoAutoElevate") { continue }

        $value = $PSBoundParameters[$key]
        if ($value -is [System.Management.Automation.SwitchParameter]) {
            if ($value.IsPresent) { $argList.Add("-$key") }
            continue
        }

        if ($value -is [array]) {
            $argList.Add("-$key")
            foreach ($item in $value) {
                $argList.Add((ConvertTo-CommandLineArgument $item))
            }
            continue
        }

        $argList.Add("-$key")
        $argList.Add((ConvertTo-CommandLineArgument $value))
    }

    Write-Warn "This operation needs Administrator rights. Relaunching elevated..."
    Start-Process -FilePath $exe -ArgumentList ($argList -join " ") -Verb RunAs | Out-Null
    exit 0
}

function Get-DefaultRegion {
    try {
        $region = [System.Globalization.RegionInfo]::CurrentRegion.TwoLetterISORegionName
        if ($region -match '^[A-Za-z]{2}$') {
            return $region.ToUpperInvariant()
        }
    } catch {
        # ignored
    }

    return "HU"
}

function Initialize-WorkingDirectories {
    foreach ($dir in @($RootDir, $BackupDir, $StagingDir, $LogDir)) {
        if (-not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
    }
}

function Grant-PolicyFileAccess {
    param([string] $Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Warn "Target path $Path does not exist. Skipping ownership and permissions grant."
        return
    }

    $administratorsSid = "*S-1-5-32-544" # Local Administrators, language-independent.
    $currentUser = "$env:USERDOMAIN\$env:USERNAME"

    Write-Info "Taking ownership of $Path"
    & takeown.exe /f $Path | Out-Host

    Write-Info "Granting Administrators full control using SID $administratorsSid"
    & icacls.exe $Path /grant "$administratorsSid`:F" | Out-Host

    Write-Info "Granting current user full control: $currentUser"
    & icacls.exe $Path /grant "$currentUser`:F" | Out-Host
}

function Read-PolicyJson {
    param([string] $Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Policy file not found: $Path"
    }

    $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    try {
        return $raw | ConvertFrom-Json
    } catch {
        throw "Failed to parse JSON at $Path. Details: $($_.Exception.Message)"
    }
}

function Write-PolicyJsonToFile {
    param(
        [Parameter(Mandatory)]
        [object] $Json,

        [Parameter(Mandatory)]
        [string] $Path
    )

    $text = $Json | ConvertTo-Json -Depth 100

    # Write UTF-8 without BOM consistently across Windows PowerShell and PowerShell 7.
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $text + [Environment]::NewLine, $utf8NoBom)

    # Validate the staged JSON immediately.
    $null = Read-PolicyJson -Path $Path
}

function Backup-PolicyFile {
    param([string] $Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Warn "Target path $Path does not exist. Skipping backup."
        return $null
    }

    Initialize-WorkingDirectories
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $backup = Join-Path $BackupDir ("IntegratedServicesRegionPolicySet.json.$stamp.bak")
    Copy-Item -LiteralPath $Path -Destination $backup -Force
    Write-Ok "Backup created: $backup"
    return $backup
}

function Ensure-PolicyFileExists {
    if (Test-Path -LiteralPath $PolicyFile) {
        return
    }

    Write-Warn "Policy file is missing at: $PolicyFile"

    # Search for backups in the same directory
    $parentDir = Split-Path -Parent $PolicyFile
    if (-not $parentDir) { $parentDir = "C:\Windows\System32" }
    
    $backupPatterns = @(
        "IntegratedServicesRegionPolicySet.backup",
        "IntegratedServicesRegionPolicySet.json.bak_*",
        "IntegratedServicesRegionPolicySet.json.bootbak_*",
        "IntegratedServicesRegionPolicySet.json.manualbak_*",
        "IntegratedServicesRegionPolicySet.json.searchv2bak_*",
        "IntegratedServicesRegionPolicySet.json.vega_bak_*"
    )

    $foundBackups = @()
    foreach ($pattern in $backupPatterns) {
        $searchPath = Join-Path $parentDir $pattern
        if (Test-Path -Path $searchPath) {
            $foundBackups += Get-Item -Path $searchPath
        }
    }

    if ($foundBackups.Count -eq 0) {
        throw "Policy file is missing and no backup files were found in $parentDir to restore from."
    }

    # Sort backups by LastWriteTime descending and pick the newest one
    $bestBackup = $foundBackups | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    Write-Info "Found backup: $($bestBackup.FullName) (Size: $($bestBackup.Length) bytes, Date: $($bestBackup.LastWriteTime))"

    if (Test-IsAdministrator) {
        Write-Info "Restoring missing policy file from backup..."
        try {
            Copy-Item -LiteralPath $bestBackup.FullName -Destination $PolicyFile -Force
            Write-Ok "Restored policy file: $PolicyFile"
        } catch {
            throw "Failed to restore policy file from backup. Error: $($_.Exception.Message)"
        }
    } else {
        Write-Warn "To automatically restore this file from backup, please run the script with administrator privileges (e.g. by running -Apply or running from an elevated console)."
    }
}

function Get-RegionSet {
    if ($AllEEA) {
        return @($EEARegionCodes)
    }

    if (-not $Region) {
        $script:Region = Get-DefaultRegion
    }

    return @($Region.ToUpperInvariant())
}

function Update-PolicyRegions {
    param(
        [Parameter(Mandatory)]
        [object] $Json,

        [Parameter(Mandatory)]
        [string[]] $Regions,

        [Parameter(Mandatory)]
        [ValidateSet("Enable", "Revert")]
        [string] $Mode
    )

    $changed = $false
    $results = @()

    foreach ($target in $TargetPolicies) {
        $matches = @($Json.policies | Where-Object { $_.guid -eq $target.Guid })

        if ($matches.Count -eq 0) {
            $results += [pscustomobject]@{
                Policy = $target.Name
                Guid = $target.Guid
                Found = $false
                Action = "Not found"
                RegionsChanged = ""
            }
            continue
        }

        foreach ($policy in $matches) {
            if (-not $policy.conditions -or -not $policy.conditions.region) {
                $results += [pscustomobject]@{
                    Policy = $target.Name
                    Guid = $target.Guid
                    Found = $true
                    Action = "No region conditions"
                    RegionsChanged = ""
                }
                continue
            }

            if (-not ($policy.conditions.region.PSObject.Properties.Name -contains "disabled")) {
                $results += [pscustomobject]@{
                    Policy = $target.Name
                    Guid = $target.Guid
                    Found = $true
                    Action = "No disabled list"
                    RegionsChanged = ""
                }
                continue
            }

            $disabled = @($policy.conditions.region.disabled)
            $before = @($disabled)

            if ($Mode -eq "Enable") {
                $disabled = @($disabled | Where-Object { $Regions -notcontains $_ })
            } else {
                foreach ($r in $Regions) {
                    if ($disabled -notcontains $r) {
                        $disabled += $r
                    }
                }
            }

            $removedOrAdded = @()
            foreach ($r in $Regions) {
                $was = $before -contains $r
                $is = $disabled -contains $r
                if ($was -ne $is) { $removedOrAdded += $r }
            }

            if ($removedOrAdded.Count -gt 0) {
                $policy.conditions.region.disabled = @($disabled)
                $changed = $true
                $action = if ($Mode -eq "Enable") { "Removed from disabled list" } else { "Added to disabled list" }
            } else {
                $action = if ($Mode -eq "Enable") { "Already enabled for region(s)" } else { "Already reverted for region(s)" }
            }

            $results += [pscustomobject]@{
                Policy = $target.Name
                Guid = $target.Guid
                Found = $true
                Action = $action
                RegionsChanged = ($removedOrAdded -join ",")
            }
        }
    }

    return [pscustomobject]@{
        Changed = $changed
        Results = $results
    }
}

function Install-PolicyFile {
    param(
        [Parameter(Mandatory)]
        [string] $ModifiedPath,

        [Parameter(Mandatory)]
        [string] $DestinationPath
    )

    if ($DryRun) {
        Write-Warn "Dry run: would install $ModifiedPath to $DestinationPath"
        return [pscustomobject]@{ Installed = $false; Scheduled = $false; RebootRequired = $false }
    }

    try {
        Copy-Item -LiteralPath $ModifiedPath -Destination $DestinationPath -Force
        Write-Ok "Policy file updated directly."
        return [pscustomobject]@{ Installed = $true; Scheduled = $false; RebootRequired = $false }
    } catch {
        Write-Warn "Direct replacement failed: $($_.Exception.Message)"
        Write-Warn "Scheduling boot-time replacement instead."

        $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $bootBackup = "$DestinationPath.bootbak_$stamp"

        $sessionManager = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager"
        $pendingName = "PendingFileRenameOperations"

        $originalNative = "\??\$DestinationPath"
        $bootBackupNative = "\??\$bootBackup"
        $modifiedNative = "\??\$ModifiedPath"

        $currentPending = @()
        try {
            $existing = Get-ItemProperty -Path $sessionManager -Name $pendingName -ErrorAction Stop
            $currentPending = @($existing.$pendingName)
        } catch {
            $currentPending = @()
        }

        # Two operations:
        # 1. Rename original protected file to boot backup.
        # 2. Rename staged modified file into original path.
        $newPending = @(
            $currentPending +
            $originalNative + $bootBackupNative +
            $modifiedNative + $originalNative
        )

        Set-ItemProperty -Path $sessionManager -Name $pendingName -Type MultiString -Value $newPending

        Write-Ok "Scheduled replacement for next boot."
        Write-Info "Boot backup will be: $bootBackup"
        return [pscustomobject]@{ Installed = $false; Scheduled = $true; RebootRequired = $true }
    }
}

function Set-SearchRegistryDefaults {
    if ($SkipRegistryTweaks) {
        Write-Warn "Skipping HKCU registry tweaks because -SkipRegistryTweaks was supplied."
        return
    }

    if ($DryRun) {
        Write-Warn "Dry run: would set Search Highlights registry defaults."
        return
    }

    Write-Info "Setting Search Highlights/taskbar search registry defaults for current user."

    & reg.exe add "HKCU\Software\Microsoft\Windows\CurrentVersion\SearchSettings" /v IsDynamicSearchBoxEnabled /t REG_DWORD /d 1 /f | Out-Host
    & reg.exe add "HKCU\Software\Microsoft\Windows\CurrentVersion\SearchSettings" /v SafeSearchMode /t REG_DWORD /d 1 /f | Out-Host
    & reg.exe add "HKCU\Software\Microsoft\Windows\CurrentVersion\Search" /v SearchboxTaskbarMode /t REG_DWORD /d 2 /f | Out-Host
    & reg.exe add "HKCU\Software\Microsoft\Windows\CurrentVersion\Search" /v BingSearchEnabled /t REG_DWORD /d 1 /f | Out-Host
    & reg.exe add "HKCU\Software\Microsoft\Windows\CurrentVersion\Search" /v CortanaConsent /t REG_DWORD /d 1 /f | Out-Host
}

function Get-KnownPolicyBlockers {
    $items = @(
        [pscustomobject]@{ Hive = "HKCU"; Path = "Software\Policies\Microsoft\Windows\Explorer"; Name = "DisableSearchBoxSuggestions"; BadValue = 1 },
        [pscustomobject]@{ Hive = "HKLM"; Path = "Software\Policies\Microsoft\Windows\Explorer"; Name = "DisableSearchBoxSuggestions"; BadValue = 1 },
        [pscustomobject]@{ Hive = "HKCU"; Path = "Software\Policies\Microsoft\Windows\Windows Search"; Name = "AllowSearchHighlights"; BadValue = 0 },
        [pscustomobject]@{ Hive = "HKLM"; Path = "Software\Policies\Microsoft\Windows\Windows Search"; Name = "AllowSearchHighlights"; BadValue = 0 }
    )

    $results = @()

    foreach ($item in $items) {
        $psPath = Join-Path ($item.Hive + ":\") $item.Path
        $value = $null
        $exists = $false
        $blocking = $false

        try {
            $prop = Get-ItemProperty -Path $psPath -Name $item.Name -ErrorAction Stop
            $value = $prop.($item.Name)
            $exists = $true
            $blocking = ([int]$value -eq [int]$item.BadValue)
        } catch {
            $exists = $false
        }

        $results += [pscustomobject]@{
            Hive = $item.Hive
            Path = $item.Path
            Name = $item.Name
            Exists = $exists
            Value = $value
            Blocking = $blocking
        }
    }

    return $results
}

function Remove-KnownPolicyBlockers {
    $blockers = Get-KnownPolicyBlockers | Where-Object { $_.Blocking }

    if ($blockers.Count -eq 0) {
        Write-Ok "No known policy blockers found."
        return
    }

    foreach ($blocker in $blockers) {
        $regPath = "$($blocker.Hive)\$($blocker.Path)"
        if ($DryRun) {
            Write-Warn "Dry run: would delete $regPath /v $($blocker.Name)"
            continue
        }

        Write-Warn "Removing blocking policy value: $regPath /v $($blocker.Name)"
        & reg.exe delete $regPath /v $blocker.Name /f 2>$null | Out-Host
    }
}

function Show-Status {
    param([string[]] $Regions)

    Write-Host ""
    Write-Host "=== $AppName status ===" -ForegroundColor Magenta
    Write-Info "Policy file: $PolicyFile"
    Write-Info "Region(s): $($Regions -join ', ')"

    $json = Read-PolicyJson -Path $PolicyFile

    $rows = @()
    foreach ($target in $TargetPolicies) {
        $matches = @($json.policies | Where-Object { $_.guid -eq $target.Guid })
        if ($matches.Count -eq 0) {
            $rows += [pscustomobject]@{
                Policy = $target.Name
                Guid = $target.Guid
                Found = $false
                DisabledForRegion = "unknown"
            }
            continue
        }

        foreach ($policy in $matches) {
            $disabled = @()
            if ($policy.conditions -and $policy.conditions.region -and ($policy.conditions.region.PSObject.Properties.Name -contains "disabled")) {
                $disabled = @($policy.conditions.region.disabled)
            }

            $stillDisabled = @($Regions | Where-Object { $disabled -contains $_ })
            $rows += [pscustomobject]@{
                Policy = $target.Name
                Guid = $target.Guid
                Found = $true
                DisabledForRegion = if ($stillDisabled.Count -gt 0) { $stillDisabled -join "," } else { "False" }
            }
        }
    }

    $rows | Format-Table -AutoSize

    Write-Host ""
    Write-Host "Known registry policy blockers:" -ForegroundColor Magenta
    Get-KnownPolicyBlockers | Format-Table -AutoSize

    Write-Host ""
    $queries = @(
        @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings"; Name = "IsDynamicSearchBoxEnabled" },
        @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings"; Name = "SafeSearchMode" },
        @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search"; Name = "SearchboxTaskbarMode" },
        @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search"; Name = "BingSearchEnabled" },
        @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search"; Name = "CortanaConsent" }
    )

    foreach ($q in $queries) {
        try {
            $prop = Get-ItemProperty -Path $q.Path -Name $q.Name -ErrorAction SilentlyContinue
            if ($null -ne $prop -and $null -ne $prop.($q.Name)) {
                Write-Host "$($q.Path) /v $($q.Name) : $($prop.($q.Name))"
            } else {
                Write-Host "Not found: $($q.Path) /v $($q.Name)"
            }
        } catch {
            Write-Host "Not found: $($q.Path) /v $($q.Name)"
        }
    }
}

function Restore-PolicyFileFromBackup {
    param([string] $BackupPath)

    if (-not (Test-Path -LiteralPath $BackupPath)) {
        throw "Backup file not found: $BackupPath"
    }

    Initialize-WorkingDirectories
    Grant-PolicyFileAccess -Path $PolicyFile

    $staged = Join-Path $StagingDir ("restore." + (Get-Date -Format "yyyyMMdd_HHmmss") + ".json")
    Copy-Item -LiteralPath $BackupPath -Destination $staged -Force
    $null = Read-PolicyJson -Path $staged

    $result = Install-PolicyFile -ModifiedPath $staged -DestinationPath $PolicyFile

    if ($result.RebootRequired) {
        Write-Warn "Restore scheduled. Reboot is required."
    } else {
        Write-Ok "Restore completed."
    }
}

function Invoke-PolicyUpdate {
    param([ValidateSet("Enable", "Revert")] [string] $Mode)

    Initialize-WorkingDirectories
    $regions = Get-RegionSet

    Write-Host ""
    Write-Host "=== $AppName ===" -ForegroundColor Magenta
    Write-Info "Policy file: $PolicyFile"
    Write-Info "Mode: $Mode"
    Write-Info "Region(s): $($regions -join ', ')"

    if (-not $Force -and -not $DryRun) {
        $verb = if ($Mode -eq "Enable") { "remove region(s) from disabled lists" } else { "add region(s) back to disabled lists" }
        $answer = Read-Host "Proceed and $verb? [Y/n]"
        if ($answer -and $answer.ToLowerInvariant() -notin @("y", "yes")) {
            Write-Warn "Cancelled."
            return
        }
    }

    $backup = Backup-PolicyFile -Path $PolicyFile
    Grant-PolicyFileAccess -Path $PolicyFile

    $json = Read-PolicyJson -Path $PolicyFile
    $update = Update-PolicyRegions -Json $json -Regions $regions -Mode $Mode

    Write-Host ""
    $update.Results | Format-Table -AutoSize

    if ($Mode -eq "Enable") {
        Set-SearchRegistryDefaults
    }

    if ($FixPolicyBlockers) {
        Remove-KnownPolicyBlockers
    } else {
        $blockers = @(Get-KnownPolicyBlockers | Where-Object { $_.Blocking })
        if ($blockers.Count -gt 0) {
            Write-Warn "Known blocking registry policy value(s) found. Re-run with -FixPolicyBlockers to remove them."
            $blockers | Format-Table -AutoSize
        }
    }

    if (-not $update.Changed) {
        Write-Ok "No JSON changes needed."
        Show-Status -Regions $regions
        return
    }

    $staged = Join-Path $StagingDir ("IntegratedServicesRegionPolicySet.modified." + (Get-Date -Format "yyyyMMdd_HHmmss") + ".json")
    Write-PolicyJsonToFile -Json $json -Path $staged
    Write-Ok "Modified JSON staged: $staged"

    $result = Install-PolicyFile -ModifiedPath $staged -DestinationPath $PolicyFile

    if (-not $result.RebootRequired) {
        Show-Status -Regions $regions
        Write-Warn "Restart Explorer/Search, or reboot if the taskbar does not refresh."
    } else {
        Write-Warn "A reboot is required to complete the file replacement."

        if (-not $NoRebootPrompt -and -not $DryRun) {
            $answer = Read-Host "Reboot now? [y/N]"
            if ($answer -and $answer.ToLowerInvariant() -in @("y", "yes")) {
                Restart-Computer
            } else {
                Write-Info "Reboot manually when convenient, then run: .\Enable-SearchGleamEEA.ps1 -Status -Region $($regions[0])"
            }
        }
    }
}

function Invoke-Interactive {
    if (-not $Region) {
        $detected = Get-DefaultRegion
        $answer = Read-Host "Region code to enable Search Gleam for [$detected]"
        if ($answer) {
            $script:Region = $answer.ToUpperInvariant()
        } else {
            $script:Region = $detected
        }
    }

    Write-Host ""
    Write-Host "What do you want to do?" -ForegroundColor Magenta
    Write-Host "  1) Apply Search Gleam patch"
    Write-Host "  2) Show status only"
    Write-Host "  3) Revert region in the three target policies"
    Write-Host "  4) Exit"
    $choice = Read-Host "Choose [1]"

    switch ($choice) {
        ""  { Invoke-PolicyUpdate -Mode Enable }
        "1" { Invoke-PolicyUpdate -Mode Enable }
        "2" { Show-Status -Regions (Get-RegionSet) }
        "3" { Invoke-PolicyUpdate -Mode Revert }
        default { Write-Warn "No changes made." }
    }
}

try {
    if (-not $Region) {
        $Region = Get-DefaultRegion
    } else {
        $Region = $Region.ToUpperInvariant()
    }

    Invoke-SelfElevationIfNeeded

    if (-not $RestoreFromBackup) {
        Ensure-PolicyFileExists
    }

    if ($Status) {
        Show-Status -Regions (Get-RegionSet)
        return
    }

    if ($RestoreFromBackup) {
        Restore-PolicyFileFromBackup -BackupPath $RestoreFromBackup
        return
    }

    if ($Apply) {
        Invoke-PolicyUpdate -Mode Enable
        return
    }

    if ($Revert) {
        Invoke-PolicyUpdate -Mode Revert
        return
    }

    Invoke-Interactive
} catch {
    Write-Fail $_.Exception.Message
    Write-Warn "No further changes will be made."
    exit 1
}
