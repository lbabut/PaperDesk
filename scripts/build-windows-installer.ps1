$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
Push-Location $projectRoot
try {
    python windows/installer.py --self-test
    if ($LASTEXITCODE -ne 0) { throw 'Package verification failed' }
    python windows/stage_product.py
    if ($LASTEXITCODE -ne 0) { throw 'Package staging failed' }
    python windows/write_version_info.py
    if ($LASTEXITCODE -ne 0) { throw 'PE version metadata generation failed' }
    $productData = "$(Join-Path $projectRoot 'build/windows-product/product');product"
    $version = (Get-Content product/VERSION -Raw).Trim()
    $versionInfo = Join-Path $projectRoot 'build/windows-version.txt'
    python -m PyInstaller --noconfirm --clean --noupx --onefile --windowed --name PaperDesk-Installer --version-file $versionInfo --add-data $productData --distpath "dist/windows/$version-prepare" --workpath build/windows --specpath build/windows-spec windows/installer.py
    if ($LASTEXITCODE -ne 0) { throw 'Installer build failed' }
    $version = (Get-Content product/VERSION -Raw).Trim()
    $exe = "dist/windows/$version-prepare/PaperDesk-Installer.exe"
    # Certificate-store identity only: never put a private-key password in a command.
    # Configure an already approved Authenticode identity; this does not buy a certificate.
    if ($env:PAPERDESK_SIGN_CERT_SHA1) {
        $signTool = if ($env:PAPERDESK_SIGNTOOL) { $env:PAPERDESK_SIGNTOOL } else { 'signtool.exe' }
        & $signTool sign /sha1 $env:PAPERDESK_SIGN_CERT_SHA1 /fd SHA256 /tr http://timestamp.digicert.com /td SHA256 $exe
        if ($LASTEXITCODE -ne 0) { throw 'Authenticode signing failed; no ZIP published' }
        & $signTool verify /pa /all $exe
        if ($LASTEXITCODE -ne 0) { throw 'Authenticode verification failed; no ZIP published' }
        if ((Get-AuthenticodeSignature $exe).Status -ne 'Valid') { throw 'Windows did not accept the signature' }
    } else {
        Write-Warning 'UNSIGNED EXE: no Authenticode identity configured. SHA-256 and Care signatures do not replace it.'
    }
    python windows/package_installer.py
    if ($LASTEXITCODE -ne 0) { throw 'Installer packaging failed' }
} finally { Pop-Location }
