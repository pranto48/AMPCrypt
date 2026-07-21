# AMPCrypt Code Signing Certificate Setup Script
# Creates a self-signed certificate, installs it to trusted stores, and exports PFX

$ErrorActionPreference = "Stop"

Write-Host "Creating AMPCrypt self-signed code signing certificate..." -ForegroundColor Cyan

# Create self-signed certificate valid for 10 years (CurrentUser — no admin needed)
$cert = New-SelfSignedCertificate `
    -Type CodeSigningCert `
    -Subject "CN=IT Support BD, O=IT Support BD, L=Dhaka, S=Dhaka, C=BD" `
    -KeyUsage DigitalSignature `
    -FriendlyName "AMPCrypt Code Signing" `
    -CertStoreLocation "Cert:\CurrentUser\My" `
    -TextExtension @("2.5.29.37={text}1.3.6.1.5.5.7.3.3", "2.5.29.19={text}") `
    -NotAfter (Get-Date).AddYears(10)

Write-Host "Certificate created. Thumbprint: $($cert.Thumbprint)" -ForegroundColor Green

# Install to CurrentUser\TrustedPeople (sufficient for MSIX sideload on this machine)
$trustedPeopleStore = New-Object System.Security.Cryptography.X509Certificates.X509Store("TrustedPeople", "CurrentUser")
$trustedPeopleStore.Open("ReadWrite")
$trustedPeopleStore.Add($cert)
$trustedPeopleStore.Close()
Write-Host "Installed to TrustedPeople\CurrentUser" -ForegroundColor Green

# Install to CurrentUser\Root (full chain trust — may show a UAC prompt, click Yes)
$rootStore = New-Object System.Security.Cryptography.X509Certificates.X509Store("Root", "CurrentUser")
$rootStore.Open("ReadWrite")
$rootStore.Add($cert)
$rootStore.Close()
Write-Host "Installed to Root\CurrentUser" -ForegroundColor Green

# Export as PFX for msix plugin signing
$pfxPassword = ConvertTo-SecureString -String "AMPCrypt2024!" -Force -AsPlainText
$pfxPath = "F:\OneDrive - arifmahmud\SynologyDrive\Website\Antigravity\AMPCrypt\ampcrypt_cert.pfx"
Export-PfxCertificate -Cert $cert -FilePath $pfxPath -Password $pfxPassword | Out-Null
Write-Host "PFX exported to: $pfxPath" -ForegroundColor Green

# Now sign the existing MSIX with the new certificate
$msixPath = "F:\OneDrive - arifmahmud\SynologyDrive\Website\Antigravity\AMPCrypt\build\windows\x64\runner\Release\ampcrypt.msix"

# Find signtool
$signtool = $null
$sdkPaths = @(
    "${env:ProgramFiles(x86)}\Windows Kits\10\bin\10.0.22621.0\x64\signtool.exe",
    "${env:ProgramFiles(x86)}\Windows Kits\10\bin\10.0.19041.0\x64\signtool.exe",
    "${env:ProgramFiles(x86)}\Windows Kits\10\bin\x64\signtool.exe"
)
foreach ($path in $sdkPaths) {
    if (Test-Path $path) {
        $signtool = $path
        break
    }
}
if (-not $signtool) {
    # Search dynamically
    $signtool = Get-ChildItem "${env:ProgramFiles(x86)}\Windows Kits\10\bin" -Recurse -Filter "signtool.exe" -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -like "*x64*" } |
        Select-Object -First 1 -ExpandProperty FullName
}

if ($signtool) {
    Write-Host "Signing MSIX with signtool: $signtool" -ForegroundColor Cyan
    & $signtool sign /fd SHA256 /a /f $pfxPath /p "AMPCrypt2024!" /tr "http://timestamp.digicert.com" /td SHA256 $msixPath
    if ($LASTEXITCODE -eq 0) {
        Write-Host "MSIX signed successfully!" -ForegroundColor Green
    } else {
        # Try without timestamp (in case no internet)
        & $signtool sign /fd SHA256 /a /f $pfxPath /p "AMPCrypt2024!" $msixPath
        if ($LASTEXITCODE -eq 0) {
            Write-Host "MSIX signed successfully (no timestamp)!" -ForegroundColor Green
        } else {
            Write-Host "Warning: signtool returned exit code $LASTEXITCODE" -ForegroundColor Yellow
        }
    }
} else {
    Write-Host "signtool.exe not found. Certificate installed but MSIX not re-signed." -ForegroundColor Yellow
    Write-Host "Use the EXE installer instead, or rebuild MSIX: flutter pub run msix:create" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=== DONE ===" -ForegroundColor Green
Write-Host "Certificate is now trusted on this machine." -ForegroundColor Green
Write-Host "Try installing ampcrypt.msix again - the certificate error should be gone." -ForegroundColor Green
Write-Host ""
Write-Host "IMPORTANT: Save the certificate thumbprint: $($cert.Thumbprint)" -ForegroundColor Yellow
