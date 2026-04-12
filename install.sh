#!/bin/bash
# =============================================================================
# Entra Audit - One-line installer
# Usage: curl -sL https://install.coderaft.io/entra-audit | bash
# =============================================================================

set -e

INSTALL_DIR="${INSTALL_DIR:-./entra-audit}"
REGISTRY="ghcr.io/liamj74"
VERSION="latest"

echo ""
echo "  ╔══════════════════════════════════════╗"
echo "  ║       Entra Audit - Installer        ║"
echo "  ║    Security Analysis Platform         ║"
echo "  ╚══════════════════════════════════════╝"
echo ""

# Check prerequisites
check_command() {
    if ! command -v "$1" &> /dev/null; then
        echo "  ✗ $1 is required but not installed."
        exit 1
    fi
    echo "  ✓ $1 found"
}

echo "  Checking prerequisites..."
check_command docker
check_command docker-compose || check_command "docker compose"
echo ""

# Create install directory
echo "  Creating installation directory: ${INSTALL_DIR}"
mkdir -p "${INSTALL_DIR}"
cd "${INSTALL_DIR}"

# Write docker-compose.yml
echo "  Writing docker-compose.yml..."
cat > docker-compose.yml << 'COMPOSE'
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
COMPOSE

# Write .env template
echo "  Writing .env configuration..."
cat > .env << 'ENVFILE'
# Entra Audit - Configuration
# The Setup Wizard at http://localhost:3000 will help you fill this in

LICENSE_KEY=
CREDENTIAL_PROVIDER=environment
AZURE_TENANT_ID=
AZURE_CLIENT_ID=
AZURE_CLIENT_SECRET=
AZURE_UI_CLIENT_ID=
NEO4J_URI=bolt://neo4j:7687
NEO4J_USER=neo4j
NEO4J_PASSWORD=audit_entra_prod
DATABASE_URL=postgresql+asyncpg://audit_entra:audit_entra_prod@postgres:5432/audit_entra
REDIS_URL=redis://redis:6379/0
CELERY_BROKER_URL=redis://redis:6379/1
CELERY_RESULT_BACKEND=redis://redis:6379/2
APP_NAME=Audit Entra
LOG_LEVEL=INFO
CORS_ORIGINS=http://localhost:3000,http://localhost:8000
REPORTS_PATH=/opt/app/reports
ENVFILE

# Write helper scripts
cat > start.sh << 'START'
#!/bin/bash
echo "Starting Entra Audit..."
docker-compose up -d
echo ""
echo "  Entra Audit is running!"
echo "  Open: http://localhost:3000"
if command -v open &> /dev/null; then open http://localhost:3000; fi
if command -v xdg-open &> /dev/null; then xdg-open http://localhost:3000; fi
START
chmod +x start.sh

cat > stop.sh << 'STOP'
#!/bin/bash
echo "Stopping Entra Audit..."
docker-compose down
echo "Done."
STOP
chmod +x stop.sh

cat > update.sh << 'UPDATE'
#!/bin/bash
echo "Updating Entra Audit..."
docker-compose pull
docker-compose up -d
echo "Updated!"
UPDATE
chmod +x update.sh

# Pull images
echo ""
echo "  Pulling Docker images (this may take a few minutes)..."
docker-compose pull

# Start services
echo ""
echo "  Starting services..."
docker-compose up -d

echo ""
echo "  Waiting for services to be ready..."
sleep 15

echo ""
echo "  ╔══════════════════════════════════════╗"
echo "  ║   Installation complete!             ║"
echo "  ║                                      ║"
echo "  ║   Open: http://localhost:3000        ║"
echo "  ║                                      ║"
echo "  ║   The Setup Wizard will guide you    ║"
echo "  ║   through the initial configuration  ║"
echo "  ╚══════════════════════════════════════╝"
echo ""
echo "  Useful commands:"
echo "    ./start.sh   - Start the application"
echo "    ./stop.sh    - Stop the application"
echo "    ./update.sh  - Update to latest version"
echo ""

# Open browser
if command -v open &> /dev/null; then
    open http://localhost:3000
elif command -v xdg-open &> /dev/null; then
    xdg-open http://localhost:3000
fi
