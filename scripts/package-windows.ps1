# Package Flutter Windows release as a portable ZIP and an Inno Setup installer.
# Run from the repository root after flutter build windows --release.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Set-Location $repoRoot
$bundle = Join-Path $repoRoot 'build/windows/x64/runner/Release'
$executable = Join-Path $bundle 'jolven_iso.exe'
$dataDirectory = Join-Path $bundle 'data'
if (-not (Test-Path -Path $executable -PathType Leaf) -or -not (Test-Path -Path $dataDirectory -PathType Container)) {
  throw 'Flutter Windows bundle ausente ou incompleto. Rode flutter build windows --release.'
}

# Include the portable Python engine as data for future WSL2/VM orchestration.
$engineTarget = Join-Path $bundle 'engine'
New-Item -ItemType Directory -Force -Path $engineTarget | Out-Null
Copy-Item -Path (Join-Path $repoRoot 'engine/jolven_iso') -Destination $engineTarget -Recurse -Force

$pubspec = Get-Content (Join-Path $repoRoot 'pubspec.yaml') -Raw
if ($pubspec -notmatch '(?m)^version:\s*([0-9]+\.[0-9]+\.[0-9]+)') {
  throw 'Nao foi possivel detectar a versao em pubspec.yaml.'
}
$version = $Matches[1]
$dist = Join-Path $repoRoot 'dist'
New-Item -ItemType Directory -Force -Path $dist | Out-Null

$zip = Join-Path $dist "Jolven-ISO-Builder-$version-Windows-x64-Portable.zip"
Compress-Archive -Path (Join-Path $bundle '*') -DestinationPath $zip -CompressionLevel Optimal -Force

$compiler = (Get-Command ISCC.exe -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source)
if (-not $compiler) {
  $compiler = Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6/ISCC.exe'
}
if (-not (Test-Path $compiler)) {
  throw 'Inno Setup 6 (ISCC.exe) nao encontrado. Instale-o antes de empacotar.'
}
& $compiler "/DAppVersion=$version" "/O$dist" (Join-Path $repoRoot 'scripts/windows-installer.iss')
if ($LASTEXITCODE -ne 0) {
  throw "Inno Setup falhou (exit code $LASTEXITCODE)."
}

$setup = Join-Path $dist "Jolven-ISO-Builder-$version-Windows-x64-Setup.exe"
if (-not (Test-Path $setup -PathType Leaf)) {
  throw 'O instalador EXE nao foi gerado.'
}
foreach ($package in @($zip, $setup)) {
  $hash = (Get-FileHash -Path $package -Algorithm SHA256).Hash.ToLowerInvariant()
  "$hash  $([System.IO.Path]::GetFileName($package))" |
    Set-Content -Path "$package.sha256" -Encoding ascii
  Write-Host "Pacote gerado: $package"
}
