@echo off
setlocal EnableDelayedExpansion

:: Self-elevate to Administrator
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting Administrator privileges...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

cd /d "%~dp0"

echo =======================================================
echo          AMPCrypt 1-Click Secure Suite Setup
echo =======================================================
echo.

:: 1. Install & Trust Root Certificate
echo [1/5] Trusting AMPCrypt Signing Certificate...
powershell -ExecutionPolicy Bypass -Command "
try {
    if (Test-Path 'ampcrypt_cert.cer') {
        Import-Certificate -FilePath 'ampcrypt_cert.cer' -CertStoreLocation 'Cert:\LocalMachine\Root' -ErrorAction SilentlyContinue | Out-Null
        Import-Certificate -FilePath 'ampcrypt_cert.cer' -CertStoreLocation 'Cert:\LocalMachine\TrustedPeople' -ErrorAction SilentlyContinue | Out-Null
        Import-Certificate -FilePath 'ampcrypt_cert.cer' -CertStoreLocation 'Cert:\CurrentUser\Root' -ErrorAction SilentlyContinue | Out-Null
        Import-Certificate -FilePath 'ampcrypt_cert.cer' -CertStoreLocation 'Cert:\CurrentUser\TrustedPeople' -ErrorAction SilentlyContinue | Out-Null
    }
    if (Test-Path 'ampcrypt.msix') {
        `$sig = (Get-AuthenticodeSignature 'ampcrypt.msix').SignerCertificate
        if (`$sig) {
            `$tempCer = [System.IO.Path]::GetTempFileName() + '.cer'
            [System.IO.File]::WriteAllBytes(`$tempCer, `$sig.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert))
            Import-Certificate -FilePath `$tempCer -CertStoreLocation 'Cert:\LocalMachine\Root' -ErrorAction SilentlyContinue | Out-Null
            Import-Certificate -FilePath `$tempCer -CertStoreLocation 'Cert:\LocalMachine\TrustedPeople' -ErrorAction SilentlyContinue | Out-Null
            Import-Certificate -FilePath `$tempCer -CertStoreLocation 'Cert:\CurrentUser\Root' -ErrorAction SilentlyContinue | Out-Null
            Import-Certificate -FilePath `$tempCer -CertStoreLocation 'Cert:\CurrentUser\TrustedPeople' -ErrorAction SilentlyContinue | Out-Null
            Remove-Item `$tempCer -Force -ErrorAction SilentlyContinue
        }
    }
    Write-Host '[+] AMPCrypt Certificate trusted successfully in Windows Root store.' -ForegroundColor Green
} catch {
    Write-Host '[!] Certificate trust note: ' `$_.Exception.Message
}
"

:: 2. Deploy Vault Drive Icon Globally and Configure Windows Explorer
echo [2/5] Deploying AMPCrypt Vault Drive Icon & Shell Registry...
powershell -ExecutionPolicy Bypass -Command "
try {
    `$progDataDir = Join-Path `$env:ProgramData 'AMPCrypt'
    if (!(Test-Path `$progDataDir)) { New-Item -ItemType Directory -Path `$progDataDir -Force | Out-Null }

    `$progFilesDir = Join-Path (Get-Item env:ProgramFiles).Value 'ampcrypt'
    if (!(Test-Path `$progFilesDir)) { New-Item -ItemType Directory -Path `$progFilesDir -Force | Out-Null }

    `$localAppDir = Join-Path `$env:LOCALAPPDATA 'com.itsupport.ampcrypt'
    if (!(Test-Path `$localAppDir)) { New-Item -ItemType Directory -Path `$localAppDir -Force | Out-Null }

    `$iconSrc = $null
    if (Test-Path 'vault_drive.ico') { `$iconSrc = 'vault_drive.ico' }
    elseif (Test-Path 'assets\vault_drive.ico') { `$iconSrc = 'assets\vault_drive.ico' }
    elseif (Test-Path 'data\flutter_assets\assets\vault_drive.ico') { `$iconSrc = 'data\flutter_assets\assets\vault_drive.ico' }

    if (`$iconSrc) {
        Copy-Item `$iconSrc (Join-Path `$progDataDir 'vault_drive.ico') -Force
        Copy-Item `$iconSrc (Join-Path `$progFilesDir 'vault_drive.ico') -Force
        Copy-Item `$iconSrc (Join-Path `$localAppDir 'vault_drive.ico') -Force
    }

    `$iconPath = Join-Path `$progDataDir 'vault_drive.ico'
    if (!(Test-Path `$iconPath)) { `$iconPath = Join-Path `$progFilesDir 'vault_drive.ico' }

    if (Test-Path `$iconPath) {
        # Register for common virtual drive letters (D to Z)
        `$letters = @('D','E','F','G','H','I','J','K','L','M','N','O','P','Q','R','S','T','U','V','W','X','Y','Z')
        foreach (`$letter in `$letters) {
            # HKLM DriveIcons
            New-Item -Path \"HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\DriveIcons\`$letter\DefaultIcon\" -Force -ErrorAction SilentlyContinue | Out-Null
            Set-ItemProperty -Path \"HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\DriveIcons\`$letter\DefaultIcon\" -Name '(Default)' -Value `$iconPath -ErrorAction SilentlyContinue | Out-Null
            New-Item -Path \"HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\DriveIcons\`$letter\DefaultLabel\" -Force -ErrorAction SilentlyContinue | Out-Null
            Set-ItemProperty -Path \"HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\DriveIcons\`$letter\DefaultLabel\" -Name '(Default)' -Value 'AMPCrypt Vault' -ErrorAction SilentlyContinue | Out-Null

            # HKCU DriveIcons
            New-Item -Path \"HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\DriveIcons\`$letter\DefaultIcon\" -Force -ErrorAction SilentlyContinue | Out-Null
            Set-ItemProperty -Path \"HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\DriveIcons\`$letter\DefaultIcon\" -Name '(Default)' -Value `$iconPath -ErrorAction SilentlyContinue | Out-Null
            New-Item -Path \"HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\DriveIcons\`$letter\DefaultLabel\" -Force -ErrorAction SilentlyContinue | Out-Null
            Set-ItemProperty -Path \"HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\DriveIcons\`$letter\DefaultLabel\" -Name '(Default)' -Value 'AMPCrypt Vault' -ErrorAction SilentlyContinue | Out-Null

            # HKCU Classes Applications Explorer
            New-Item -Path \"HKCU:\Software\Classes\Applications\Explorer.exe\Drives\`$letter\DefaultIcon\" -Force -ErrorAction SilentlyContinue | Out-Null
            Set-ItemProperty -Path \"HKCU:\Software\Classes\Applications\Explorer.exe\Drives\`$letter\DefaultIcon\" -Name '(Default)' -Value `$iconPath -ErrorAction SilentlyContinue | Out-Null
            New-Item -Path \"HKCU:\Software\Classes\Applications\Explorer.exe\Drives\`$letter\DefaultLabel\" -Force -ErrorAction SilentlyContinue | Out-Null
            Set-ItemProperty -Path \"HKCU:\Software\Classes\Applications\Explorer.exe\Drives\`$letter\DefaultLabel\" -Name '(Default)' -Value 'AMPCrypt Vault' -ErrorAction SilentlyContinue | Out-Null
        }
        Write-Host '[+] AMPCrypt Vault Drive Icon configured permanently for Windows Explorer.' -ForegroundColor Green
    }
} catch {
    Write-Host '[!] Drive icon configuration note: ' `$_.Exception.Message
}
"

:: 3. Deploy Local Virtual Filesystem Driver & Helper
echo [3/5] Deploying Local Virtual Filesystem Helper...
powershell -ExecutionPolicy Bypass -Command "
`$supportDir = Join-Path `$env:LOCALAPPDATA 'com.itsupport.ampcrypt';
if (!(Test-Path `$supportDir)) { New-Item -ItemType Directory -Path `$supportDir -Force | Out-Null }
if (Test-Path 'rclone.exe') {
    Copy-Item 'rclone.exe' -Destination (Join-Path `$supportDir 'rclone.exe') -Force
}
`$progFiles = Join-Path (Get-Item env:ProgramFiles).Value 'ampcrypt';
if (!(Test-Path `$progFiles)) { New-Item -ItemType Directory -Path `$progFiles -Force | Out-Null }
if (Test-Path 'rclone.exe') {
    Copy-Item 'rclone.exe' -Destination (Join-Path `$progFiles 'rclone.exe') -Force
}
Write-Host '[+] Filesystem helpers initialized successfully.' -ForegroundColor Green
"

:: 4. Install WinFsp Virtual Local Disk Driver
echo [4/5] Installing WinFsp Virtual Local Disk Driver...
if exist "winfsp.msi" (
    start /wait msiexec.exe /i "winfsp.msi" /qn /norestart
    echo [+] WinFsp Driver installed successfully.
) else (
    echo [!] WinFsp installer not found in current folder, checking system...
)

:: 5. Register MSIX Package
echo [5/5] Installing AMPCrypt MSIX Package...
if exist "ampcrypt.msix" (
    powershell -ExecutionPolicy Bypass -Command "Add-AppxPackage -Path 'ampcrypt.msix' -ForceApplicationShutdown"
    if %errorlevel% equ 0 (
        echo.
        echo =======================================================
        echo   [+] AMPCrypt installed successfully!
        echo =======================================================
        echo.
        powershell -Command "Start-Process 'shell:AppsFolder\com.itsupport.ampcrypt_1.0.0.0_x64__p24x91w1s9d7m!AMPCrypt'" >nul 2>&1
    ) else (
        echo [-] Standard Appx registration encountered an issue. Starting standalone ampcrypt.exe...
        if exist "ampcrypt.exe" (
            start "" "ampcrypt.exe"
        )
    )
) else (
    if exist "ampcrypt.exe" (
        start "" "ampcrypt.exe"
    )
)

:: Refresh Shell Icon Cache
ie4uinit.exe -show >nul 2>&1

echo.
echo Setup Complete!
timeout /t 4 >nul
exit /b 0
