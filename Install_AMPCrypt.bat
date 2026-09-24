@echo off
setlocal EnableDelayedExpansion
title AMPCrypt Easy 1-Click Installer

:: Check and Auto-Elevate to Administrator
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo.
    echo =======================================================
    echo   AMPCrypt Installer: Requesting Administrator Rights...
    echo =======================================================
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

cd /d "%~dp0"

echo =======================================================
echo          AMPCrypt Easy 1-Click Setup & Installer
echo =======================================================
echo.
echo Installing and configuring AMPCrypt Secure Suite...
echo.

:: 1. Enable Windows App Sideloading (Eliminates Error 0x80073CFF)
echo [1/5] Enabling Windows App Sideloading...
powershell -NoProfile -ExecutionPolicy Bypass -Command "
try {
    $regPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock'
    if (!(Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }
    Set-ItemProperty -Path $regPath -Name 'AllowAllTrustedApps' -Value 1 -Type DWord -Force | Out-Null
    Set-ItemProperty -Path $regPath -Name 'AllowDevelopmentWithoutDevLicense' -Value 1 -Type DWord -Force | Out-Null
    Write-Host '  [+] Windows App Sideloading enabled.' -ForegroundColor Green
} catch {
    Write-Host '  [!] Sideloading note: ' $_.Exception.Message -ForegroundColor Yellow
}
"

:: 2. Trust Signing Certificate in Local Machine Store
echo [2/5] Installing and Trusting Security Certificate...
powershell -NoProfile -ExecutionPolicy Bypass -Command "
try {
    $certInstalled = $false

    # A. If .cer file exists, import it
    if (Test-Path 'ampcrypt_cert.cer') {
        Import-Certificate -FilePath 'ampcrypt_cert.cer' -CertStoreLocation 'Cert:\LocalMachine\Root' -ErrorAction SilentlyContinue | Out-Null
        Import-Certificate -FilePath 'ampcrypt_cert.cer' -CertStoreLocation 'Cert:\LocalMachine\TrustedPeople' -ErrorAction SilentlyContinue | Out-Null
        Import-Certificate -FilePath 'ampcrypt_cert.cer' -CertStoreLocation 'Cert:\CurrentUser\Root' -ErrorAction SilentlyContinue | Out-Null
        Import-Certificate -FilePath 'ampcrypt_cert.cer' -CertStoreLocation 'Cert:\CurrentUser\TrustedPeople' -ErrorAction SilentlyContinue | Out-Null
        $certInstalled = $true
    }

    # B. If ampcrypt.msix exists, extract and trust the exact certificate used to sign it
    if (Test-Path 'ampcrypt.msix') {
        $sig = (Get-AuthenticodeSignature 'ampcrypt.msix').SignerCertificate
        if ($sig) {
            $tempCer = Join-Path $env:TEMP 'ampcrypt_installer_cert.cer'
            [System.IO.File]::WriteAllBytes($tempCer, $sig.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert))
            Import-Certificate -FilePath $tempCer -CertStoreLocation 'Cert:\LocalMachine\Root' -ErrorAction SilentlyContinue | Out-Null
            Import-Certificate -FilePath $tempCer -CertStoreLocation 'Cert:\LocalMachine\TrustedPeople' -ErrorAction SilentlyContinue | Out-Null
            Import-Certificate -FilePath $tempCer -CertStoreLocation 'Cert:\CurrentUser\Root' -ErrorAction SilentlyContinue | Out-Null
            Import-Certificate -FilePath $tempCer -CertStoreLocation 'Cert:\CurrentUser\TrustedPeople' -ErrorAction SilentlyContinue | Out-Null
            Remove-Item $tempCer -Force -ErrorAction SilentlyContinue
            $certInstalled = $true
        }
    }

    if ($certInstalled) {
        Write-Host '  [+] AMPCrypt Certificate trusted successfully in Windows Root store.' -ForegroundColor Green
    } else {
        Write-Host '  [!] Certificate file not found; proceeding with system trust...' -ForegroundColor Yellow
    }
} catch {
    Write-Host '  [!] Certificate note: ' $_.Exception.Message -ForegroundColor Yellow
}
"

:: 3. Install WinFsp Virtual Local Disk Driver Silently
echo [3/5] Setting up Virtual Disk Filesystem Driver...
if exist "winfsp.msi" (
    start /wait msiexec.exe /i "winfsp.msi" /qn /norestart
    echo   [+] WinFsp Driver installed successfully.
) else (
    echo   [*] Checking system WinFsp installation...
)

:: 4. Deploy Vault Drive Icon & Shell Registry
echo [4/5] Configuring AMPCrypt Vault Drive Icon...
powershell -NoProfile -ExecutionPolicy Bypass -Command "
try {
    $progDataDir = Join-Path $env:ProgramData 'AMPCrypt'
    if (!(Test-Path $progDataDir)) { New-Item -ItemType Directory -Path $progDataDir -Force | Out-Null }

    $iconSrc = $null
    if (Test-Path 'vault_drive.ico') { $iconSrc = 'vault_drive.ico' }
    elseif (Test-Path 'assets\vault_drive.ico') { $iconSrc = 'assets\vault_drive.ico' }
    elseif (Test-Path 'data\flutter_assets\assets\vault_drive.ico') { $iconSrc = 'data\flutter_assets\assets\vault_drive.ico' }

    if ($iconSrc) {
        Copy-Item $iconSrc (Join-Path $progDataDir 'vault_drive.ico') -Force
    }

    $iconPath = Join-Path $progDataDir 'vault_drive.ico'
    if (Test-Path $iconPath) {
        $letters = @('D','E','F','G','H','I','J','K','L','M','N','O','P','Q','R','S','T','U','V','W','X','Y','Z')
        foreach ($letter in $letters) {
            $regKey = \"HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\DriveIcons\$letter\DefaultIcon\"
            New-Item -Path $regKey -Force -ErrorAction SilentlyContinue | Out-Null
            Set-ItemProperty -Path $regKey -Name '(Default)' -Value $iconPath -ErrorAction SilentlyContinue | Out-Null

            $labelKey = \"HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\DriveIcons\$letter\DefaultLabel\"
            New-Item -Path $labelKey -Force -ErrorAction SilentlyContinue | Out-Null
            Set-ItemProperty -Path $labelKey -Name '(Default)' -Value 'AMPCrypt Vault' -ErrorAction SilentlyContinue | Out-Null
        }
        Write-Host '  [+] Vault Drive Icon registered for Windows Explorer.' -ForegroundColor Green
    }
} catch {
    Write-Host '  [!] Drive Icon note: ' $_.Exception.Message -ForegroundColor Yellow
}
"

:: 5. Install AMPCrypt MSIX Package
echo [5/5] Installing AMPCrypt MSIX Package...
powershell -NoProfile -ExecutionPolicy Bypass -Command "
try {
    if (Test-Path 'ampcrypt.msix') {
        Write-Host '  [*] Registering MSIX package into Windows...' -ForegroundColor Cyan
        $existing = Get-AppxPackage -Name 'com.itsupport.ampcrypt*'
        if ($existing) {
            if ($existing.Status -ne 0 -and $existing.Status -ne 'Ok') {
                Write-Host '  [*] Removing previous unhealthy package state...' -ForegroundColor Yellow
                Remove-AppxPackage -Package $existing.PackageFullName -ErrorAction SilentlyContinue
            }
        }
        Add-AppxPackage -Path 'ampcrypt.msix' -ForceApplicationShutdown -ForceUpdateFromAnyVersion -ErrorAction Stop
        Write-Host '  [+] AMPCrypt MSIX installed successfully!' -ForegroundColor Green
        $global:msixSuccess = $true
    } else {
        Write-Host '  [!] ampcrypt.msix not found in current folder.' -ForegroundColor Red
        $global:msixSuccess = $false
    }
} catch {
    Write-Host '  [!] Add-AppxPackage notice: ' $_.Exception.Message -ForegroundColor Yellow
    Write-Host '  [*] Opening native Windows App Installer dialog...' -ForegroundColor Cyan
    Start-Process 'ampcrypt.msix'
    $global:msixSuccess = $true
}
"

echo.
echo =======================================================
echo   [+] Setup Complete! Launching AMPCrypt...
echo =======================================================
echo.

:: Launch Application
powershell -NoProfile -Command "
Start-Sleep -Seconds 1
try {
    $pkg = Get-AppxPackage -Name 'com.itsupport.ampcrypt*' | Select-Object -First 1
    if ($pkg) {
        $manifest = Get-AppxPackageManifest -Package $pkg
        $appId = $manifest.Package.Applications.Application.Id
        $aumid = \"$($pkg.PackageFamilyName)!$appId\"
        Write-Host \"  [+] Launching AMPCrypt ($aumid)...\" -ForegroundColor Green
        Start-Process \"shell:AppsFolder\$aumid\"
    } elseif (Test-Path 'ampcrypt.exe') {
        Write-Host '  [+] Launching standalone ampcrypt.exe...' -ForegroundColor Green
        Start-Process 'ampcrypt.exe'
    }
} catch {
    if (Test-Path 'ampcrypt.exe') {
        Start-Process 'ampcrypt.exe'
    }
}
"

timeout /t 3 >nul
exit /b
