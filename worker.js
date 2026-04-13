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
        '/entraguard': 'https://raw.githubusercontent.com/LiamJ74/entra-audit-installer/master/install.sh',
        '/entraguard.ps1': 'https://raw.githubusercontent.com/LiamJ74/entra-audit-installer/master/install.ps1',
        '/ravenscan': 'https://raw.githubusercontent.com/LiamJ74/ravenscan-installer/master/install.sh',
        '/ravenscan.ps1': 'https://raw.githubusercontent.com/LiamJ74/ravenscan-installer/master/install.ps1',
        // Legacy aliases
        '/entra-audit': 'https://raw.githubusercontent.com/LiamJ74/entra-audit-installer/master/install.sh',
        '/secaudit': 'https://raw.githubusercontent.com/LiamJ74/ravenscan-installer/master/install.sh',
      };

      // Racine → page d'aide
      if (path === '/') {
        return new Response(
`CodeRaft Installer

Usage (Linux / macOS):
  curl -sL https://install.coderaft.io/entraguard | bash
  curl -sL https://install.coderaft.io/ravenscan | bash

Usage (Windows / PowerShell):
  irm https://install.coderaft.io/entraguard.ps1 | iex
  irm https://install.coderaft.io/ravenscan.ps1 | iex
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
