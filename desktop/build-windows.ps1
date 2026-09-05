param(
    [string]$Runtime = "win-x64",
    [string]$Configuration = "Release"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$project = Join-Path $root "IMail.Desktop\IMail.Desktop.csproj"
$out = Join-Path $root "artifacts\$Runtime"

Write-Host "Publishing iMail Desktop for $Runtime..." -ForegroundColor Green
if (Test-Path $out) { Remove-Item $out -Recurse -Force }
New-Item -ItemType Directory -Force -Path $out | Out-Null

dotnet restore $project
dotnet publish $project `
  -c $Configuration `
  -r $Runtime `
  --self-contained true `
  -p:PublishSingleFile=true `
  -p:IncludeNativeLibrariesForSelfExtract=true `
  -p:PublishTrimmed=false `
  -o $out

Write-Host ""
Write-Host "iMail Desktop published successfully:" -ForegroundColor Green
Write-Host $out
Write-Host "Run iMail.exe to test the application."

$iscc = Get-Command iscc.exe -ErrorAction SilentlyContinue
if ($iscc) {
    Write-Host "Building installer with Inno Setup..." -ForegroundColor Green
    & $iscc.Source (Join-Path $root "installer\imail.iss")
} else {
    Write-Host "Inno Setup not found. The portable/self-contained build is ready; install Inno Setup to create Setup.exe." -ForegroundColor Yellow
}
