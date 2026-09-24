# Copyright (c) IT Support BD (https://itsupport.com.bd). All rights reserved.
# This file is part of AMPCrypt.
# This program is free software but it under the terms of the GNU Affero General Public License.
# (This project website link: https://ampcrypt.itsupport.com.bd)

$cert = $null
if (Test-Path "ampcrypt_cert.cer") {
    $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2("ampcrypt_cert.cer")
} elseif (Test-Path "ampcrypt.msix") {
    $sig = (Get-AuthenticodeSignature "ampcrypt.msix").SignerCertificate
    if ($sig) { $cert = $sig }
}
if (-not $cert) {
    $cert = Get-ChildItem "Cert:\CurrentUser\My" -ErrorAction SilentlyContinue | Where-Object { $_.Subject -like "*CN=IT Support BD*" } | Select-Object -First 1
}

if ($cert) {
    $store1 = New-Object System.Security.Cryptography.X509Certificates.X509Store("TrustedPeople", "CurrentUser")
    $store1.Open("ReadWrite")
    $store1.Add($cert)
    $store1.Close()

    $store2 = New-Object System.Security.Cryptography.X509Certificates.X509Store("Root", "CurrentUser")
    $store2.Open("ReadWrite")
    $store2.Add($cert)
    $store2.Close()

    Write-Host "Cert successfully added to CurrentUser\TrustedPeople and Root" -ForegroundColor Green
} else {
    Write-Host "AMPCrypt Certificate not found!" -ForegroundColor Red
}
