# Stop on non-terminating errors
$ErrorActionPreference = "Stop"

$discordProcessName = "discord"
$downloadUrl = "https://github.com/hdrover/discord-drover/releases/download/v0.8/drover-v0.8.zip"
$zipFileName = "drover-v0.8.zip"
$remoteScriptUrl = "https://raw.githubusercontent.com/shadowpercifal/pwsh-simple/refs/heads/main/droverinstall.ps1"

# Check if current process runs as admin
function Test-IsAdmin {
    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Relaunch script as admin
function Relaunch-AsAdmin {
    param([string]$ScriptPath, [switch]$IsRemote)

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "powershell.exe"
    if ($IsRemote) {
        # If running via iex, download the script and run via temp file
        $tempScript = Join-Path $env:TEMP "droverinstall_temp.ps1"
        Invoke-WebRequest -Uri $remoteScriptUrl -OutFile $tempScript -UseBasicParsing
        $psi.Arguments = "-ExecutionPolicy Bypass -File `"$tempScript`""
    } else {
        $psi.Arguments = "-ExecutionPolicy Bypass -File `"$ScriptPath`""
    }
    $psi.Verb = "runas" # triggers UAC
    try {
        [System.Diagnostics.Process]::Start($psi) | Out-Null
        exit
    } catch {
        throw "Administrator privileges are required to terminate elevated Discord processes."
    }
}

# Detect if running via iex (no script path)
$runningViaIEX = [string]::IsNullOrEmpty($MyInvocation.MyCommand.Path)

try {
    # Get all Discord processes
    $discordProcesses = Get-Process -Name $discordProcessName -ErrorAction SilentlyContinue
    if (-not $discordProcesses) {
        throw "Discord process was not found. Please start Discord and try again."
    }

    # Attempt to kill all processes non-elevated
    $needAdmin = $false
    foreach ($proc in $discordProcesses) {
        try {
            Stop-Process -Id $proc.Id -Force -ErrorAction Stop
        } catch {
            $needAdmin = $true
            break
        }
    }

    # Relaunch with admin if needed
    if ($needAdmin -and -not (Test-IsAdmin)) {
        if ($runningViaIEX) {
            Write-Host "Running via iex. Relaunching script with admin privileges..."
            Relaunch-AsAdmin -IsRemote
        } else {
            Write-Host "Relaunching script with admin privileges..."
            Relaunch-AsAdmin -ScriptPath $MyInvocation.MyCommand.Path
        }
    }

    # Re-fetch Discord processes and ensure they are terminated
    $discordProcesses = Get-Process -Name $discordProcessName -ErrorAction SilentlyContinue
    if ($discordProcesses) {
        foreach ($proc in $discordProcesses) {
            Stop-Process -Id $proc.Id -Force
        }
    }

    # Wait until all Discord processes are fully stopped
    while (Get-Process -Name $discordProcessName -ErrorAction SilentlyContinue) {
        Start-Sleep -Milliseconds 300
    }
    Write-Host "All Discord processes have been terminated."

    # Determine Discord directory
    $discordExePath = ($discordProcesses | Where-Object { $_.Path } | Select-Object -First 1).Path
    if (-not $discordExePath) {
        # Fallback: standard install location
        $discordExePath = Get-ChildItem "$env:LOCALAPPDATA\Discord\app-*\Discord.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $discordExePath) { throw "Unable to determine Discord installation path." }
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
