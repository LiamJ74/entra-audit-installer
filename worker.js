// =============================================================================
// CodeRaft Installer — Cloudflare Worker
// Routes install.coderaft.io/<product> to the correct install script
// =============================================================================

const REPO_BASE = 'https://raw.githubusercontent.com/LiamJ74/entra-audit-installer/main';

const PRODUCTS = {
  '/entra-audit': {
    script: `${REPO_BASE}/entra-audit.sh`,
    name: 'Entra Audit',
  },
  // '/secaudit': {
  //   script: `${REPO_BASE}/secaudit.sh`,
  //   name: 'SecAudit',
  // },
};

const HELP_TEXT = `
  ╔══════════════════════════════════════╗
  ║     CodeRaft Installer              ║
  ╚══════════════════════════════════════╝

  Usage:

    curl -sL https://install.coderaft.io/entra-audit | bash

  Available products:

    /entra-audit    Entra ID Security Audit Tool

  More info: https://coderaft.io
`;

export default {
  async fetch(request) {
    const url = new URL(request.url);
    const path = url.pathname.replace(/\/+$/, '') || '/';

    // Root — show help
    if (path === '/') {
      return new Response(HELP_TEXT, {
        headers: { 'content-type': 'text/plain; charset=utf-8' },
      });
    }

    // Known product — proxy the install script
    const product = PRODUCTS[path];
    if (product) {
      const resp = await fetch(product.script, {
        headers: { 'User-Agent': 'CodeRaft-Installer/1.0' },
      });

      if (!resp.ok) {
        return new Response(`Error: failed to fetch ${product.name} installer.\n`, {
          status: 502,
          headers: { 'content-type': 'text/plain' },
        });
      }

      return new Response(resp.body, {
        headers: {
          'content-type': 'text/plain; charset=utf-8',
          'cache-control': 'public, max-age=300',
          'x-product': product.name,
        },
      });
    }

    // Unknown product
    const available = Object.keys(PRODUCTS).map((p) => `    ${p}`).join('\n');
    return new Response(
      `Unknown product: ${path}\n\nAvailable products:\n${available}\n\nUsage: curl -sL https://install.coderaft.io/entra-audit | bash\n`,
      {
        status: 404,
        headers: { 'content-type': 'text/plain; charset=utf-8' },
      },
    );
  },
};
