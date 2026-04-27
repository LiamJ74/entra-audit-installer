export default {
  async fetch(request, env, ctx) {
    try {
      const url = new URL(request.url);
      let path = url.pathname;

      // Normalise le path (mais garde "/" intact)
      if (path.length > 1 && path.endsWith('/')) {
        path = path.slice(0, -1);
      }

      const scripts = {
        // Unified platform installer (dashboard deploys products based on license)
        '/': 'https://raw.githubusercontent.com/LiamJ74/coderaft-installer/master/install.sh',
        '/win': 'https://raw.githubusercontent.com/LiamJ74/coderaft-installer/master/install.ps1',
        // Per-product installers
        '/entraguard': 'https://raw.githubusercontent.com/LiamJ74/entra-audit-installer/master/install.sh',
        '/entraguard.ps1': 'https://raw.githubusercontent.com/LiamJ74/entra-audit-installer/master/install.ps1',
        '/ravenscan': 'https://raw.githubusercontent.com/LiamJ74/ravenscan-installer/master/install.sh',
        '/ravenscan.ps1': 'https://raw.githubusercontent.com/LiamJ74/ravenscan-installer/master/install.ps1',
        '/redfox': 'https://raw.githubusercontent.com/LiamJ74/coderaft-installer/master/install.sh',
        '/redfox.ps1': 'https://raw.githubusercontent.com/LiamJ74/coderaft-installer/master/install.ps1',
        // Update scripts (self-updating)
        '/update': 'https://raw.githubusercontent.com/LiamJ74/coderaft-installer/master/scripts/update.sh',
        '/update.ps1': 'https://raw.githubusercontent.com/LiamJ74/coderaft-installer/master/scripts/update.ps1',
        // Per-product update scripts
        '/ravenscan/update': 'https://raw.githubusercontent.com/LiamJ74/ravenscan-installer/master/scripts/update.sh',
        '/ravenscan/update.ps1': 'https://raw.githubusercontent.com/LiamJ74/ravenscan-installer/master/scripts/update.ps1',
        '/entraguard/update': 'https://raw.githubusercontent.com/LiamJ74/entra-audit-installer/master/scripts/update.sh',
        '/entraguard/update.ps1': 'https://raw.githubusercontent.com/LiamJ74/entra-audit-installer/master/scripts/update.ps1',
        // Legacy aliases
        '/entra-audit': 'https://raw.githubusercontent.com/LiamJ74/entra-audit-installer/master/install.sh',
        '/secaudit': 'https://raw.githubusercontent.com/LiamJ74/ravenscan-installer/master/install.sh',
      };

      // Racine → serve unified installer script (for curl | bash)
      // Browser visitors get help text instead
      const ua = request.headers.get('user-agent') || '';
      if (path === '/' && (ua.includes('Mozilla') || ua.includes('Chrome'))) {
        return new Response(
`CodeRaft Platform Installer

Install (Linux / macOS):
  curl -fsSL https://install.coderaft.io | bash

Install (Windows / PowerShell):
  irm https://install.coderaft.io/win | iex

Update (Linux / macOS):
  curl -fsSL https://install.coderaft.io/update | bash

Update (Windows / PowerShell):
  irm https://install.coderaft.io/update.ps1 | iex

The installer deploys the CodeRaft Dashboard.
Activate your license in the dashboard to deploy your products.
`,
          { headers: { 'content-type': 'text/plain; charset=utf-8' } }
        );
      }

      const target = scripts[path];

      if (!target) {
        return new Response(
`Unknown product: ${path}

Available:
  /entraguard
  /ravenscan
  /redfox
`,
          {
            status: 404,
            headers: { 'content-type': 'text/plain; charset=utf-8' },
          }
        );
      }

      // Cache Cloudflare
      const cache = caches.default;
      const cacheKey = new Request(request.url, request);
      let response = await cache.match(cacheKey);

      if (response) {
        return response;
      }

      const resp = await fetch(target, {
        headers: {
          'User-Agent': 'CodeRaft-Installer',
          'Accept': 'text/plain',
        },
      });

      if (!resp.ok) {
        return new Response(
          `Failed to fetch installer script (${resp.status}).\n`,
          { status: 502 }
        );
      }

      response = new Response(resp.body, {
        status: 200,
        headers: {
          'content-type': 'text/plain; charset=utf-8',
          'cache-control': 'public, max-age=300',
        },
      });

      ctx.waitUntil(cache.put(cacheKey, response.clone()));

      return response;

    } catch (err) {
      return new Response(
        `Internal error: ${err.message}\n`,
        { status: 500 }
      );
    }
  },
};
