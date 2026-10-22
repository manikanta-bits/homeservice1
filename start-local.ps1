$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$javaHome = 'C:\tools\jdk21\jdk-21.0.8+9'
$mavenBin = 'C:\tools\apache-maven-3.9.9\bin'
$nodeBin = 'C:\tools\node-v22.15.0-win-x64'
$mysqlName = 'sahayak-mysql-local'
$mysqlPassword = 'sahayak_root_local'

function Test-Url([string] $Url) {
    try {
        $null = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 3
        return $true
    } catch {
        return $false
    }
}

function Test-Docker {
    docker info --format '{{.ServerVersion}}' *> $null
    return $LASTEXITCODE -eq 0
}

if (-not (Test-Docker)) {
    $dockerDesktop = 'C:\Program Files\Docker\Docker\Docker Desktop.exe'
    if (-not (Test-Path $dockerDesktop)) {
        throw 'Docker Desktop is not installed. Install Docker Desktop, restart Windows, and run this launcher again.'
    }

    Start-Process -FilePath $dockerDesktop
    $dockerReady = $false
    for ($attempt = 0; $attempt -lt 60; $attempt++) {
        Start-Sleep -Seconds 2
        if (Test-Docker) {
            $dockerReady = $true
            break
        }
    }
    if (-not $dockerReady) {
        throw 'Docker Desktop did not start. Open Docker Desktop, wait until it says it is running, then run this launcher again.'
    }
}

Push-Location $root
try {
    docker compose up -d redis mailpit
    if ($LASTEXITCODE -ne 0) {
        throw 'Could not start Redis and Mailpit. Check Docker Desktop and try again.'
    }
} finally {
    Pop-Location
}

$mysqlExists = docker ps -a --format '{{.Names}}' | Where-Object { $_ -eq $mysqlName }
if ($mysqlExists) {
    $mysqlRunning = docker ps --format '{{.Names}}' | Where-Object { $_ -eq $mysqlName }
    if (-not $mysqlRunning) {
        docker start $mysqlName *> $null
        if ($LASTEXITCODE -ne 0) {
            throw 'Could not start the Sahayak database container.'
        }
    }
} else {
    docker run -d --name $mysqlName --restart unless-stopped `
        -e MYSQL_DATABASE=sahayak `
        -e MYSQL_USER=sahayak `
        -e MYSQL_PASSWORD=sahayak_dev_pw `
        -e "MYSQL_ROOT_PASSWORD=$mysqlPassword" `
        -p 3307:3306 `
        -v sahayak-mysql-local-data:/var/lib/mysql `
        mysql:8.4
    if ($LASTEXITCODE -ne 0) {
        throw 'Could not create the Sahayak database container.'
    }
}

$databaseReady = $false
for ($attempt = 0; $attempt -lt 60; $attempt++) {
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'SilentlyContinue'
    docker exec $mysqlName mysqladmin ping -h 127.0.0.1 -uroot "-p$mysqlPassword" --silent 2>$null
    $mysqlPingExitCode = $LASTEXITCODE
    $ErrorActionPreference = $previousErrorActionPreference
    if ($mysqlPingExitCode -eq 0) {
        $databaseReady = $true
        break
    }
    Start-Sleep -Seconds 2
}
if (-not $databaseReady) {
    throw 'The Sahayak database did not become ready. Keep Docker Desktop open and try again.'
}

$apiUrl = 'http://localhost:8080/actuator/health'
if (-not (Test-Url $apiUrl)) {
    if (-not (Test-Path (Join-Path $javaHome 'bin\java.exe'))) {
        throw "Java 21 was not found at $javaHome."
    }
    if (-not (Test-Path (Join-Path $mavenBin 'mvn.cmd'))) {
        throw "Maven was not found at $mavenBin."
    }

    $backend = Join-Path $root 'backend'
    $apiCommand = "`$env:JAVA_HOME='$javaHome'; `$env:Path='$javaHome\bin;$mavenBin;' + `$env:Path; `$env:SPRING_DATASOURCE_URL='jdbc:mysql://localhost:3307/sahayak?useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=UTC'; Set-Location '$backend'; mvn spring-boot:run '-Dspring-boot.run.profiles=local'"
    Start-Process -FilePath 'powershell.exe' -ArgumentList @(
        '-NoExit',
        '-ExecutionPolicy', 'Bypass',
        '-Command', $apiCommand
    )

    $apiReady = $false
    for ($attempt = 0; $attempt -lt 60; $attempt++) {
        Start-Sleep -Seconds 2
        if (Test-Url $apiUrl) {
            $apiReady = $true
            break
        }
    }
    if (-not $apiReady) {
        throw 'The API did not start. Check the new backend PowerShell window for the error.'
    }
}

$webUrl = 'http://localhost:5173'
if (-not (Test-Url $webUrl)) {
    if (-not (Test-Path (Join-Path $nodeBin 'npm.cmd'))) {
        throw "Node.js was not found at $nodeBin."
    }
    if (-not (Test-Path (Join-Path $root 'web\node_modules\vite'))) {
        throw 'Web app packages are missing. Open a terminal in the web folder and run npm install.'
    }

    $web = Join-Path $root 'web'
    $webCommand = "`$env:Path='$nodeBin;' + `$env:Path; Set-Location '$web'; npm run dev"
    Start-Process -FilePath 'powershell.exe' -ArgumentList @(
        '-NoExit',
        '-ExecutionPolicy', 'Bypass',
        '-Command', $webCommand
    )

    $webReady = $false
    for ($attempt = 0; $attempt -lt 30; $attempt++) {
        Start-Sleep -Seconds 1
        if (Test-Url $webUrl) {
            $webReady = $true
            break
        }
    }
    if (-not $webReady) {
        throw 'The website did not start. Check the new web PowerShell window for the error.'
    }
}

Write-Host ''
Write-Host 'Sahayak is ready.'
Write-Host "Website:      $webUrl"
Write-Host 'Email inbox:  http://localhost:8025'
Write-Host "API health:   $apiUrl"
Start-Process $webUrl
