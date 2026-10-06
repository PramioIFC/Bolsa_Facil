param([ValidateRange(1, 65535)][int]$ProxyPort = 8081)

$ErrorActionPreference = 'Stop'
$projectDirectory = $PSScriptRoot
$proxy = $null
$dartCommand = (Get-Command dart -ErrorAction Stop).Source
$dartSdkExe = Join-Path (Split-Path $dartCommand) 'cache/dart-sdk/bin/dart.exe'
if (-not (Test-Path -LiteralPath $dartSdkExe)) { $dartSdkExe = $dartCommand }
$logDirectory = Join-Path $projectDirectory '.tool-data'
New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
$proxyErrors = Join-Path $logDirectory 'proxy.stderr.log'

try {
    Write-Host "Iniciando proxy seguro da brapi em http://localhost:$ProxyPort..."
    $proxy = Start-Process `
        -FilePath $dartSdkExe `
        -ArgumentList @('--disable-dart-dev', 'tool/brapi_proxy.dart', "--port=$ProxyPort") `
        -WorkingDirectory $projectDirectory `
        -WindowStyle Hidden `
        -RedirectStandardOutput (Join-Path $logDirectory 'proxy.stdout.log') `
        -RedirectStandardError $proxyErrors `
        -PassThru

    $ready = $false
    for ($attempt = 0; $attempt -lt 50; $attempt++) {
        if ($proxy.HasExited) {
            throw "O proxy não iniciou. Confira a porta $ProxyPort e o token no .env. Log: $proxyErrors"
        }
        try {
            $health = Invoke-RestMethod -Uri "http://127.0.0.1:$ProxyPort/health" -TimeoutSec 1
            if ($health.ok) { $ready = $true; break }
        } catch { }
        Start-Sleep -Milliseconds 200
    }
    if (-not $ready) { throw "O proxy não ficou disponível. Log: $proxyErrors" }

    Write-Host 'Iniciando Bolsa Fácil no Chrome...'
    Push-Location -LiteralPath $projectDirectory
    try {
        $chromeDataDir = Join-Path $projectDirectory '.chrome-data'
        flutter run -d chrome --web-port 3000 --dart-define="BRAPI_BASE_URL=http://localhost:$ProxyPort/api" --web-browser-flag="--user-data-dir=$chromeDataDir"
    } finally { Pop-Location }
}
finally {
    if ($null -ne $proxy -and -not $proxy.HasExited) {
        # Encerra apenas o processo criado aqui e seus filhos.
        & taskkill.exe /PID $proxy.Id /T /F | Out-Null
    }
}
