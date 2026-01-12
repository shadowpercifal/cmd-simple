# Stop on non-terminating errors
$ErrorActionPreference = "Stop"

$discordProcessName = "discord"
$downloadUrl = "https://github.com/hdrover/discord-drover/releases/download/v0.8/drover-v0.8.zip"
$zipFileName = "drover-v0.8.zip"

# Check if current process runs as admin
function Test-IsAdmin {
    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Relaunch script as admin
function Relaunch-AsAdmin {
    param([string]$ScriptPath)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "powershell.exe"
    $psi.Arguments = "-ExecutionPolicy Bypass -File `"$ScriptPath`""
    $psi.Verb = "runas"
    try {
        [System.Diagnostics.Process]::Start($psi) | Out-Null
        exit
    } catch {
        throw "Administrator privileges are required to terminate elevated Discord processes."
    }
}

try {
    # Get all Discord processes
    $discordProcesses = Get-Process -Name $discordProcessName -ErrorAction SilentlyContinue

    if (-not $discordProcesses) {
        throw "Discord process was not found. Please start Discord and try again."
    }

    # Check if any Discord process is elevated
    $needAdmin = $false
    foreach ($proc in $discordProcesses) {
        $processHandle = $proc.Handle
        try {
            # Attempt to kill a single process non-elevated
            Stop-Process -Id $proc.Id -Force -ErrorAction Stop
        } catch {
            $needAdmin = $true
            break
        }
    }

    # Relaunch as admin if required
    if ($needAdmin -and -not (Test-IsAdmin)) {
        Write-Host "Some Discord processes require administrative privileges to terminate."
        Relaunch-AsAdmin -ScriptPath $MyInvocation.MyCommand.Path
    }

    # Re-fetch Discord processes and terminate any remaining
    $discordProcesses = Get-Process -Name $discordProcessName -ErrorAction SilentlyContinue
    if ($discordProcesses) {
        foreach ($proc in $discordProcesses) {
            Stop-Process -Id $proc.Id -Force
        }
    }

    # Wait until all Discord processes disappear
    while (Get-Process -Name $discordProcessName -ErrorAction SilentlyContinue) {
        Start-Sleep -Milliseconds 300
    }

    Write-Host "All Discord processes have been terminated."

    # Determine Discord directory
    $discordExePath = ($discordProcesses | Where-Object { $_.Path } | Select-Object -First 1).Path
    if (-not $discordExePath) {
        # Fallback: check standard install locations
        $discordExePath = "$env:LOCALAPPDATA\Discord\app-*\Discord.exe"
        $discordExePath = Get-ChildItem -Path $discordExePath -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $discordExePath) {
            throw "Unable to determine Discord installation path."
        }
        $discordExePath = $discordExePath.FullName
    }

    $discordDir = Split-Path -Path $discordExePath -Parent
    $zipPath = Join-Path $discordDir $zipFileName

    Write-Host "Discord directory: $discordDir"

    # Download ZIP
    Write-Host "Downloading archive..."
    Invoke-WebRequest -Uri $downloadUrl -OutFile $zipPath -UseBasicParsing

    # Extract version.dll
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead($zipPath)

    $versionDllEntry = $zip.Entries | Where-Object { $_.Name -ieq "version.dll" } | Select-Object -First 1
    if (-not $versionDllEntry) {
        $zip.Dispose()
        throw "version.dll was not found in the downloaded archive."
    }

    $destinationDllPath = Join-Path $discordDir "version.dll"
    Write-Host "Extracting version.dll to $destinationDllPath"
    [System.IO.Compression.ZipFileExtensions]::ExtractToFile($versionDllEntry, $destinationDllPath, $true)
    $zip.Dispose()

    # Remove ZIP archive
    Remove-Item -Path $zipPath -Force

    Write-Host ""
    Write-Host "version.dll has been successfully extracted. You may now restart Discord."

} catch {
    Write-Error $_.Exception.Message
}
