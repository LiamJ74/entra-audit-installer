export default {
  async fetch(request) {
    try {
      const url = new URL(request.url);
      let path = url.pathname;

      // Normalise le path (mais garde "/" intact)
      if (path.length > 1 && path.endsWith('/')) {
        path = path.slice(0, -1);
      }

      const scripts = {
        '/entra-audit': 'https://raw.githubusercontent.com/LiamJ74/entra-audit-installer/main/install.sh',
        '/secaudit': 'https://raw.githubusercontent.com/LiamJ74/secaudit-installer/main/install.sh',
      };

      // Racine → page d'aide
      if (path === '/') {
        return new Response(
`CodeRaft Installer

Usage:
  curl -sL https://install.coderaft.io/entra-audit | bash
  curl -sL https://install.coderaft.io/secaudit | bash
`,
          { headers: { 'content-type': 'text/plain; charset=utf-8' } }
        );
      }

      const target = scripts[path];

      if (!target) {
        return new Response(
`Unknown product: ${path}

Available:
  /entra-audit
  /secaudit
`,
          {
            status: 404,
            headers: { 'content-type': 'text/plain; charset=utf-8' },
          }
        );
      }

      // Proxy le script depuis GitHub
      const resp = await fetch(target);

      if (!resp.ok) {
        return new Response(
          `Failed to fetch installer script (${resp.status}).\n`,
          { status: 502 }
        );
      }

      return new Response(resp.body, {
        status: resp.status,
        headers: {
          'content-type': 'text/plain; charset=utf-8',
          'cache-control': 'public, max-age=300',
        },
      });

    } catch (err) {
      return new Response(
        `Internal error: ${err.message}\n`,
        { status: 500 }
      );
    }
  },
};
