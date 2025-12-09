<# start-pr.ps1 Usage: .\start-pr.ps1 <pr-number> #>
param(
  [Parameter(Mandatory=$true)]
  [int]$PR
)

function Fail($msg) { Write-Host $msg -ForegroundColor Red; exit 1 }

if ($PR -lt 1 -or $PR -gt 60000) { Fail "PR must be between 1 and 60000." }

# compute ports
$WEB_PORT = 3000 + $PR
$API1_PORT = 5000 + $PR
$API2_PORT = 5100 + $PR
$NGINX_PORT = 8000 + $PR
$POSTGRES_PORT = 5400 + $PR
$REDIS_PORT = 6400 + $PR

foreach ($p in @($WEB_PORT,$API1_PORT,$API2_PORT,$NGINX_PORT,$POSTGRES_PORT,$REDIS_PORT)) {
  if ($p -ge 65535) { Fail "Computed port $p >= 65535. Choose smaller PR." }
}

$envfile = ".\env.pr$PR"
$project = "pr$PR"

$envContent = @"
WEB_PORT=$WEB_PORT
NGINX_PORT=$NGINX_PORT
API1_PORT=$API1_PORT
API2_PORT=$API2_PORT
POSTGRES_PORT=$POSTGRES_PORT
REDIS_PORT=$REDIS_PORT
PG_USER=postgres
PG_PASSWORD=postgres
PG_DB=review_db
"@
Set-Content -Path $envfile -Value $envContent -Encoding UTF8

Write-Host "Generated $envfile"
Write-Host "Starting compose for project $project ..."

$upArgs = @("compose","--env-file",$envfile,"-p",$project,"up","-d","--build")
& docker @upArgs
if ($LASTEXITCODE -ne 0) { Fail "docker compose up failed." }

function Wait-Url($url, $timeoutSec) {
  $deadline = (Get-Date).AddSeconds($timeoutSec)
  while ((Get-Date) -lt $deadline) {
    try {
      $r = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 5 -ErrorAction SilentlyContinue
      if ($r -and $r.StatusCode -in 200,503) { return $true }  # Принимаем 503 как "живой, но не готов"
    } catch {}
    Start-Sleep -Seconds 3  # Увеличил sleep для меньше нагрузки
  }
  return $false
}

# Сначала ждём Postgres и Redis (60s max)
Write-Host "Waiting for Postgres..."
$okPg = $false
$pgDeadline = (Get-Date).AddSeconds(60)
while ((Get-Date) -lt $pgDeadline) {
  $pgCheck = & docker exec "$project-postgres-1" pg_isready -U postgres
  if ($pgCheck -match "accepting connections") { $okPg = $true; break }
  Start-Sleep -Seconds 5
}

Write-Host "Waiting for Redis..."
$okRedis = $false
$redisDeadline = (Get-Date).AddSeconds(60)
while ((Get-Date) -lt $redisDeadline) {
  $redisCheck = & docker exec "$project-redis-1" redis-cli ping
  if ($redisCheck -eq "PONG") { $okRedis = $true; break }
  Start-Sleep -Seconds 5
}

# Затем API и nginx (увеличил timeout до 180s)
$api1Url = "http://localhost:$API1_PORT/health"
$api2Url = "http://localhost:$API2_PORT/health"
$nginxUrl = "http://localhost:$NGINX_PORT/"

Write-Host "Waiting for API1: $api1Url"
$ok1 = Wait-Url $api1Url 180
Write-Host "Waiting for API2: $api2Url"
$ok2 = Wait-Url $api2Url 180
Write-Host "Waiting for nginx: $nginxUrl"
$ok3 = Wait-Url $nginxUrl 60

if ($okPg -and $okRedis -and $ok1 -and $ok2 -and $ok3) {
  Write-Host "Environment $project is UP." -ForegroundColor Green
} else {
  Write-Host "WARNING: Some services didn't pass health checks." -ForegroundColor Yellow
  if (-not $okPg) { Write-Host "Postgres failed" }
  if (-not $okRedis) { Write-Host "Redis failed" }
  if (-not $ok1) { Write-Host "API1 failed: $api1Url" }
  if (-not $ok2) { Write-Host "API2 failed: $api2Url" }
  if (-not $ok3) { Write-Host "NGINX failed: $nginxUrl" }
}

Write-Host ""
Write-Host "=============================="
Write-Host ("Access URLs for {0}:" -f $project)
Write-Host (" Frontend (via nginx): http://localhost:{0}" -f $NGINX_PORT)
Write-Host (" API1 (direct): http://localhost:{0}" -f $API1_PORT)
Write-Host (" API2 (direct): http://localhost:{0}" -f $API2_PORT)
Write-Host "=============================="
Write-Host ""
Write-Host "To stop: .\stop-pr.ps1 $PR"
Write-Host "Check logs: docker logs $project-api1-1"