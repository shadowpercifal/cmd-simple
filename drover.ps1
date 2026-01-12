# Stop on non-terminating errors
$ErrorActionPreference = "Stop"

$discordProcessName = "discord"
$downloadUrl = "https://github.com/hdrover/discord-drover/releases/download/v0.8/drover-v0.8.zip"
$zipFileName = "drover-v0.8.zip"

function Test-IsAdmin {
    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Relaunch script as admin with output/error capture
function Relaunch-AsAdmin {
    param([string]$ScriptContent)
    Write-Host "Re-launching script with administrative privileges..."

    $tempFile = Join-Path $env:TEMP ("temp_admin_script_" + [Guid]::NewGuid().ToString() + ".ps1")
    Set-Content -Path $tempFile -Value $ScriptContent -Force

    $outFile = Join-Path $env:TEMP ("temp_admin_output_" + [Guid]::NewGuid().ToString() + ".txt")
    $errFile = Join-Path $env:TEMP ("temp_admin_error_" + [Guid]::NewGuid().ToString() + ".txt")

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "powershell.exe"
    $psi.Arguments = "-ExecutionPolicy Bypass -File `"$tempFile`" *> `"$outFile`" 2> `"$errFile`""
    $psi.Verb = "runas"
    $psi.UseShellExecute = $true

    try {
        $proc = [System.Diagnostics.Process]::Start($psi)
        $proc.WaitForExit()

        # Show output and errors to user
        if (Test-Path $outFile) {
            $outText = Get-Content $outFile -Raw
            if ($outText) { Write-Host "`n--- Elevated Output ---`n$outText" }
            Remove-Item $outFile -Force
        }
        if (Test-Path $errFile) {
            $errText = Get-Content $errFile -Raw
            if ($errText) { Write-Host "`n--- Elevated Errors ---`n$errText" }
            Remove-Item $errFile -Force
        }

        # Remove temp script
        Remove-Item $tempFile -Force

        exit
    } catch {
        throw "Administrator privileges are required to terminate elevated Discord processes."
    }
}

function Wait-DiscordExit {
    while (Get-Process -Name $discordProcessName -ErrorAction SilentlyContinue) {
        Start-Sleep -Milliseconds 300
    }
}

try {
    # Capture script content
    $scriptContent = $MyInvocation.MyCommand.Path | ForEach-Object { Get-Content -Raw -ErrorAction SilentlyContinue }
    if (-not $scriptContent) { $scriptContent = $MyInvocation.Line }

    # Get all Discord processes
    $discordProcesses = Get-Process -Name $discordProcessName -ErrorAction SilentlyContinue
    if (-not $discordProcesses) {
        throw "Discord process was not found. Please start Discord and try again."
    }

    # Attempt to stop Discord; if fails, relaunch elevated
    $needAdmin = $false
    foreach ($proc in $discordProcesses) {
        try { Stop-Process -Id $proc.Id -Force -ErrorAction Stop } catch { $needAdmin = $true; break }
    }

    if ($needAdmin -and -not (Test-IsAdmin)) {
        if (-not $scriptContent) { throw "Cannot elevate: script content unavailable." }
        Relaunch-AsAdmin -ScriptContent $scriptContent
    }

    Wait-DiscordExit()
    Write-Host "All Discord processes have been terminated."

    # Determine Discord directory
    $discordExePath = ($discordProcesses | Where-Object { $_.Path } | Select-Object -First 1).Path
    if (-not $discordExePath) {
        $discordExePath = Get-ChildItem -Path "$env:LOCALAPPDATA\Discord\app-*\Discord.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
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
    if (-not $versionDllEntry) { $zip.Dispose(); throw "version.dll was not found in the downloaded archive." }

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
