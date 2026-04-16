# coderaft.io Installer Infrastructure -- Claude context

This repo serves double duty:

1. **Cloudflare Worker** routing for `install.coderaft.io` (serves ALL coderaft products)
2. **EntraGuard installer scripts** (`install.sh` / `install.ps1`)

## Cloudflare Worker (`worker.js`)

Routes requests from `install.coderaft.io` to raw GitHub URLs:

| Route | Target |
|---|---|
| `/entraguard` | `LiamJ74/entra-audit-installer/master/install.sh` |
| `/entraguard.ps1` | `LiamJ74/entra-audit-installer/master/install.ps1` |
| `/ravenscan` | `LiamJ74/ravenscan-installer/master/install.sh` |
| `/ravenscan.ps1` | `LiamJ74/ravenscan-installer/master/install.ps1` |
| `/redfox`, `/redfox.ps1` | To be added when RedFox is ready |

Legacy aliases (`/entra-audit`, `/secaudit`) also exist -- do not remove.

- **Cache TTL**: ~5 minutes (`max-age=300`). After pushing changes, either wait or purge Cloudflare cache.
- **Deployment**: Cloudflare Dashboard or `wrangler deploy`.
- **Root `/`**: Returns a plain-text usage page.

## EntraGuard installer (`install.sh` / `install.ps1`)

The scripts:
1. Check prerequisites (Docker, Docker Compose v2)
2. Create install directory (`./entraguard` by default)
3. Write `docker-compose.yml` with services: api, worker, beat, postgres, neo4j, redis, frontend
4. Generate `.env` with a `TENANT_ENCRYPTION_KEY` (preserves existing `.env` on reinstall)
5. Write helper scripts: `start.sh`, `stop.sh`, `update.sh`
6. Pull images and run `docker compose up -d`

Images: `ghcr.io/liamj74/entra-audit-api:latest`, `ghcr.io/liamj74/entra-audit-worker:latest`, `ghcr.io/liamj74/entra-audit-frontend:latest`.

## Conventions

- Branch is `master` (not `main`). The Cloudflare Worker URLs hardcode `/master/` in the path.
- All coderaft installer routes live in this single worker, not separate workers per product.

## Adding a new product (e.g. RedFox)

1. Create `LiamJ74/redfox-installer` repo with `install.sh` and `install.ps1`
2. Add `/redfox` and `/redfox.ps1` routes in `worker.js`
3. Deploy the worker (`wrangler deploy`)
