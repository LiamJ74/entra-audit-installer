# =============================================================================
# EntraGuard - One-line installer (PowerShell)
# Usage: irm https://install.coderaft.io/entraguard.ps1 | iex
# =============================================================================

$ErrorActionPreference = 'Stop'

$InstallDir = if ($env:INSTALL_DIR) { $env:INSTALL_DIR } else { 'entraguard' }

Write-Host ""
Write-Host "  ╔══════════════════════════════════════╗"
Write-Host "  ║       EntraGuard - Installer        ║"
Write-Host "  ║    Security Analysis Platform        ║"
Write-Host "  ╚══════════════════════════════════════╝"
Write-Host ""

function Test-Command($name) {
    if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
        Write-Host "  ✗ $name is required but not installed." -ForegroundColor Red
        exit 1
    }
    Write-Host "  ✓ $name found" -ForegroundColor Green
}

Write-Host "  Checking prerequisites..."
Test-Command docker
# "docker compose" is a subcommand of docker on modern installs
& docker compose version *> $null
if ($LASTEXITCODE -ne 0) {
    Write-Host "  ✗ 'docker compose' plugin is required." -ForegroundColor Red
    exit 1
}
Write-Host "  ✓ docker compose found" -ForegroundColor Green
Write-Host ""

Write-Host "  Creating installation directory: $InstallDir"
New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
Set-Location $InstallDir

Write-Host "  Writing docker-compose.yml..."
$Compose = @'
services:
  api:
    image: ghcr.io/liamj74/entra-audit-api:latest
    ports:
      - "8000:8000"
    env_file:
      - .env
    depends_on:
      postgres:
        condition: service_healthy
      neo4j:
        condition: service_healthy
      redis:
        condition: service_healthy
    volumes:
      - reports_data:/opt/app/reports
      - ./.env:/opt/app/.env
    restart: unless-stopped

  worker:
    image: ghcr.io/liamj74/entra-audit-worker:latest
    command: celery -A app.celery_app worker --loglevel=info --concurrency=2
    env_file:
      - .env
    depends_on:
      postgres:
        condition: service_healthy
      neo4j:
        condition: service_healthy
      redis:
        condition: service_healthy
    volumes:
      - reports_data:/opt/app/reports
      - ./.env:/opt/app/.env
    restart: unless-stopped

  beat:
    image: ghcr.io/liamj74/entra-audit-worker:latest
    command: celery -A app.celery_app beat --loglevel=info
    env_file:
      - .env
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    volumes:
      - ./.env:/opt/app/.env
    restart: unless-stopped

  postgres:
    image: postgres:16-alpine
    environment:
      POSTGRES_USER: audit_entra
      POSTGRES_PASSWORD: audit_entra_prod
      POSTGRES_DB: audit_entra
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U audit_entra"]
      interval: 5s
      timeout: 5s
      retries: 5
    restart: unless-stopped

  neo4j:
    image: neo4j:5-community
    environment:
      NEO4J_AUTH: neo4j/audit_entra_prod
      NEO4J_PLUGINS: '["apoc"]'
      NEO4J_dbms_security_procedures_unrestricted: apoc.*
      NEO4J_dbms_security_procedures_allowlist: apoc.*
    volumes:
      - neo4j_data:/data
    healthcheck:
      test: ["CMD-SHELL", "cypher-shell -u neo4j -p audit_entra_prod 'RETURN 1' || exit 1"]
      interval: 10s
      timeout: 10s
      retries: 10
      start_period: 30s
    restart: unless-stopped

  redis:
    image: redis:7-alpine
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      timeout: 5s
      retries: 5
    restart: unless-stopped

  frontend:
    image: ghcr.io/liamj74/entra-audit-frontend:latest
    ports:
      - "3000:3000"
    depends_on:
      - api
    restart: unless-stopped

volumes:
  postgres_data:
  neo4j_data:
  reports_data:
'@
Set-Content -Path 'docker-compose.yml' -Value $Compose -Encoding UTF8

# Preserve an existing master key if the user is reinstalling, otherwise
# generate a fresh random one. This key is REQUIRED to decrypt the license
# and Azure client_secret stored in the database.
$MasterKey = $null
if (Test-Path '.env') {
    $ExistingLine = Select-String -Path '.env' -Pattern '^TENANT_ENCRYPTION_KEY=' -SimpleMatch:$false -List
    if ($ExistingLine) {
        $MasterKey = ($ExistingLine.Line -replace '^TENANT_ENCRYPTION_KEY=', '').Trim()
    }
}
if (-not $MasterKey) {
    $bytes = New-Object byte[] 32
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    $MasterKey = [Convert]::ToBase64String($bytes)
}

# .env is infrastructure-only. Secrets (license, Azure client_secret) live
# encrypted in the database using TENANT_ENCRYPTION_KEY as the master key.
# Stealing .env alone or the DB alone both yield nothing.
Write-Host "  Writing .env configuration..."
$Env = @"
# EntraGuard - Configuration
# The Setup Wizard at http://localhost:3000 will help you fill this in
# Secrets (license key, Azure client_secret) are NEVER stored here anymore.
# They live encrypted in the database; this file only holds the master key.

TENANT_ENCRYPTION_KEY=$MasterKey
CREDENTIAL_PROVIDER=environment
AZURE_TENANT_ID=
AZURE_CLIENT_ID=
AZURE_UI_CLIENT_ID=
NEO4J_URI=bolt://neo4j:7687
NEO4J_USER=neo4j
NEO4J_PASSWORD=audit_entra_prod
DATABASE_URL=postgresql+asyncpg://audit_entra:audit_entra_prod@postgres:5432/audit_entra
REDIS_URL=redis://redis:6379/0
CELERY_BROKER_URL=redis://redis:6379/1
CELERY_RESULT_BACKEND=redis://redis:6379/2
APP_NAME=EntraGuard
LOG_LEVEL=INFO
CORS_ORIGINS=http://localhost:3000,http://localhost:8000
REPORTS_PATH=/opt/app/reports
"@
Set-Content -Path '.env' -Value $Env -Encoding UTF8

# Helper scripts
Set-Content -Path 'start.ps1' -Value @'
Write-Host "Starting EntraGuard..."
docker compose up -d
Write-Host ""
Write-Host "  EntraGuard is running!"
Write-Host "  Open: http://localhost:3000"
Start-Process "http://localhost:3000"
'@ -Encoding UTF8

Set-Content -Path 'stop.ps1' -Value @'
Write-Host "Stopping EntraGuard..."
docker compose down
Write-Host "Done."
'@ -Encoding UTF8

Set-Content -Path 'update.ps1' -Value @'
Write-Host "Updating EntraGuard..."
docker compose pull
docker compose up -d
Write-Host "Updated!"
'@ -Encoding UTF8

Write-Host ""
Write-Host "  Pulling Docker images (this may take a few minutes)..."
docker compose pull

Write-Host ""
Write-Host "  Starting services..."
docker compose up -d

Write-Host ""
Write-Host "  Waiting for services to be ready..."
Start-Sleep -Seconds 15

Write-Host ""
Write-Host "  ╔══════════════════════════════════════╗"
Write-Host "  ║   Installation complete!             ║"
Write-Host "  ║                                      ║"
Write-Host "  ║   Open: http://localhost:3000        ║"
Write-Host "  ║                                      ║"
Write-Host "  ║   The Setup Wizard will guide you    ║"
Write-Host "  ║   through the initial configuration  ║"
Write-Host "  ╚══════════════════════════════════════╝"
Write-Host ""
Write-Host "  Useful commands:"
Write-Host "    .\start.ps1   - Start the application"
Write-Host "    .\stop.ps1    - Stop the application"
Write-Host "    .\update.ps1  - Update to latest version"
Write-Host ""

Start-Process "http://localhost:3000"
