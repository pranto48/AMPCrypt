# AMPCrypt Autonomous Windows Installer
param(
    [switch]$LaunchAfterInstall = $true
)

$ErrorActionPreference = "Stop"
Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host "       AMPCrypt Windows Application Installer         " -ForegroundColor Cyan
Write-Host "=======================================================" -ForegroundColor Cyan

$sourceDir = Resolve-Path "Clients software\Standalone_Portable"
$installDir = Join-Path $env:LOCALAPPDATA "Programs\AMPCrypt"
$desktopDir = [Environment]::GetFolderPath("Desktop")
$startMenuDir = [Environment]::GetFolderPath("Programs")

Write-Host "Source directory:  $sourceDir" -ForegroundColor Gray
Write-Host "Install directory: $installDir" -ForegroundColor Gray

# 1. Close any running instances if open
Write-Host "`n[1/6] Checking for running instances of AMPCrypt..." -ForegroundColor Yellow
$running = Get-Process -Name "ampcrypt" -ErrorAction SilentlyContinue
if ($running) {
    Write-Host "  Stopping running instance (PID: $($running.Id))..." -ForegroundColor Yellow
    Stop-Process -Name "ampcrypt" -Force
    Start-Sleep -Seconds 1
}

# 2. Deploy application files to %LOCALAPPDATA%\Programs\AMPCrypt
Write-Host "`n[2/6] Deploying application binaries and assets..." -ForegroundColor Yellow
if (-not (Test-Path $installDir)) {
    New-Item -ItemType Directory -Path $installDir -Force | Out-Null
}

Copy-Item -Path "$sourceDir\*" -Destination $installDir -Recurse -Force
Write-Host "  [+] All binaries, plugins, and runtime assets deployed." -ForegroundColor Green

# 3. Create Windows Start Menu Shortcut
Write-Host "`n[3/6] Creating Start Menu Shortcut..." -ForegroundColor Yellow
$wsh = New-Object -ComObject WScript.Shell
$startShortcutPath = Join-Path $startMenuDir "AMPCrypt.lnk"
$startShortcut = $wsh.CreateShortcut($startShortcutPath)
$startShortcut.TargetPath = Join-Path $installDir "ampcrypt.exe"
$startShortcut.WorkingDirectory = $installDir
$startShortcut.Description = "AMPCrypt Zero-Trust Encrypted Cloud & Local Vault"
$iconFile = Join-Path $installDir "vault_drive.ico"
if (Test-Path $iconFile) {
    $startShortcut.IconLocation = "$iconFile,0"
}
$startShortcut.Save()
Write-Host "  [+] Start Menu shortcut created: $startShortcutPath" -ForegroundColor Green

# 4. Create Desktop Shortcut
Write-Host "`n[4/6] Creating Desktop Shortcut..." -ForegroundColor Yellow
$desktopShortcutPath = Join-Path $desktopDir "AMPCrypt.lnk"
$desktopShortcut = $wsh.CreateShortcut($desktopShortcutPath)
$desktopShortcut.TargetPath = Join-Path $installDir "ampcrypt.exe"
$desktopShortcut.WorkingDirectory = $installDir
$desktopShortcut.Description = "AMPCrypt Zero-Trust Encrypted Cloud & Local Vault"
if (Test-Path $iconFile) {
    $desktopShortcut.IconLocation = "$iconFile,0"
}
$desktopShortcut.Save()
Write-Host "  [+] Desktop shortcut created: $desktopShortcutPath" -ForegroundColor Green

# 5. Register in Windows Installed Applications (Settings > Apps & Features)
Write-Host "`n[5/6] Registering AMPCrypt in Windows Apps list..." -ForegroundColor Yellow
$uninstallKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\AMPCrypt"
if (-not (Test-Path $uninstallKey)) {
    New-Item -Path $uninstallKey -Force | Out-Null
}
Set-ItemProperty -Path $uninstallKey -Name "DisplayName" -Value "AMPCrypt Zero-Trust Vault" -Force
Set-ItemProperty -Path $uninstallKey -Name "DisplayVersion" -Value "1.0.0" -Force
Set-ItemProperty -Path $uninstallKey -Name "Publisher" -Value "IT Support BD" -Force
Set-ItemProperty -Path $uninstallKey -Name "InstallLocation" -Value $installDir -Force
Set-ItemProperty -Path $uninstallKey -Name "DisplayIcon" -Value (Join-Path $installDir "vault_drive.ico") -Force
Set-ItemProperty -Path $uninstallKey -Name "UninstallString" -Value "powershell -Command Remove-Item -Recurse -Force '$installDir'; Remove-Item -Force '$startShortcutPath'; Remove-Item -Force '$desktopShortcutPath'; Remove-Item -Path '$uninstallKey' -Recurse" -Force
Write-Host "  [+] Windows Settings registry updated successfully." -ForegroundColor Green

# 6. Verify Installation and Test Launch
Write-Host "`n[6/6] Verifying installation..." -ForegroundColor Yellow
$installedExe = Join-Path $installDir "ampcrypt.exe"
if (Test-Path $installedExe) {
    $fileInfo = Get-Item $installedExe
    Write-Host "  [+] Verified Executable: $installedExe" -ForegroundColor Green
    Write-Host "  [+] Size: $($fileInfo.Length) bytes ($([Math]::Round($fileInfo.Length / 1MB, 2)) MB)" -ForegroundColor Green
    Write-Host "  [+] Timestamp: $($fileInfo.LastWriteTime)" -ForegroundColor Green

    if ($LaunchAfterInstall) {
        Write-Host "`nLaunching AMPCrypt application..." -ForegroundColor Cyan
        Start-Process -FilePath $installedExe -WorkingDirectory $installDir
        Start-Sleep -Seconds 2
        $proc = Get-Process -Name "ampcrypt" -ErrorAction SilentlyContinue
        if ($proc) {
            Write-Host "  [+] AMPCrypt is actively running! (PID: $($proc.Id))" -ForegroundColor Green
        } else {
            Write-Host "  [*] Process launched." -ForegroundColor Yellow
        }
    }
} else {
    Write-Host "  [!] Error: Executable not found at $installedExe" -ForegroundColor Red
    exit 1
}

Write-Host "`n=======================================================" -ForegroundColor Green
Write-Host "     AMPCrypt Installation Completed Successfully!    " -ForegroundColor Green
Write-Host "=======================================================" -ForegroundColor Green
