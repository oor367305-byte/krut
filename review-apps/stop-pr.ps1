param(
  [Parameter(Mandatory=$true)]
  [int]$PR
)

$PROJECT = "pr$PR"
$envfile = ".\.env.pr$PR"

Write-Host "Stopping project $PROJECT ..."
docker compose --env-file $envfile -p $PROJECT down -v

if (Test-Path $envfile) {
  Remove-Item $envfile -Force
  Write-Host "Removed $envfile"
}

Write-Host "Stopped."
