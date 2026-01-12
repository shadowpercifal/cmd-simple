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
    param([string]$ScriptContent)
    Write-Host "Re-launching script with administrative privileges..."

    $tempFile = Join-Path $env:TEMP ("temp_admin_script_" + [Guid]::NewGuid().ToString() + ".ps1")
    Set-Content -Path $tempFile -Value $ScriptContent -Force

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "powershell.exe"
    $psi.Arguments = "-ExecutionPolicy Bypass -File `"$tempFile`""
    $psi.Verb = "runas"
    try {
        [System.Diagnostics.Process]::Start($psi) | Out-Null
        exit
    } catch {
        throw "Administrator privileges are required to terminate elevated Discord processes."
    }
}

# Helper: Wait for all discord.exe to terminate
function Wait-DiscordExit {
    while (Get-Process -Name $discordProcessName -ErrorAction SilentlyContinue) {
        Start-Sleep -Milliseconds 300
    }
}

try {
    # Capture the full script content for potential re-launch
    $scriptContent = Get-Content -Raw -LiteralPath $MyInvocation.MyCommand.Path -ErrorAction SilentlyContinue
    if (-not $scriptContent) {
        # Running in memory (unsaved), read from invocation
        $scriptContent = $MyInvocation.Line
    }

    # Get all Discord processes
    $discordProcesses = Get-Process -Name $discordProcessName -ErrorAction SilentlyContinue
    if (-not $discordProcesses) {
        throw "Discord process was not found. Please start Discord and try again."
    }

    # Attempt to stop Discord; if fails, relaunch as admin
    $needAdmin = $false
    foreach ($proc in $discordProcesses) {
        try {
            Stop-Process -Id $proc.Id -Force -ErrorAction Stop
        } catch {
            $needAdmin = $true
            break
        }
    }

    if ($needAdmin -and -not (Test-IsAdmin)) {
        if (-not $scriptContent) {
            throw "Cannot elevate: script content is unavailable."
        }
        Relaunch-AsAdmin -ScriptContent $scriptContent
    }

    # Ensure all Discord processes terminated
    Wait-DiscordExit()
    Write-Host "All Discord processes have been terminated."

    # Determine Discord directory
    $discordExePath = ($discordProcesses | Where-Object { $_.Path } | Select-Object -First 1).Path
    if (-not $discordExePath) {
        # Fallback: common install location
        $discordExePath = Get-ChildItem -Path "$env:LOCALAPPDATA\Discord\app-*\Discord.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
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
