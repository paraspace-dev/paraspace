# Workspace URLs

Out of the box, a workspace named `my-feature` is served at
`https://my-feature.paraspace.dev:8443` — no DNS setup, no privileged ports,
no configuration. Every part of that URL is adjustable:

- the **`:8443`** can go away ([remove the port](#removing-the-port));
- **`paraspace.dev`** can be [your own domain](#using-your-own-domain);
- the certificate comes from `para` Caddy's local CA, which your browser needs to
  [trust once](#trusting-the-certificate).

## Removing the port

`para`'s Caddy binds `:8443` by default because any user can. For clean,
port-less URLs (`https://my-feature.paraspace.dev`), move it to `:443`:

```sh
para config-set PARA_HTTPS_PORT 443
```

On Linux, non-root can't bind ports below 1024, so also grant the caddy binary
the bind capability (re-apply after a `caddy` upgrade):

```sh
sudo setcap cap_net_bind_service=+ep "$(readlink -f "$(command -v caddy)")"
```

macOS allows the bind as-is — the `config-set` alone is enough. Then re-run
`para start`; `para start` warns with the exact fix if the capability is
missing.

## Using your own domain

Workspaces resolve at `<name>.$PARA_DOMAIN`. The default `paraspace.dev`
wildcards to `127.0.0.1`, which is why it works with zero setup. To serve
under your own domain instead:

1. Point a wildcard `*.<your-domain> → 127.0.0.1` in your DNS.
2. Set `PARA_DOMAIN` in the project's `Parafile`.

## Trusting the certificate

`para` Caddy serves the wildcard with its own internal CA, so browsers distrust
it until that root is installed — `para start` reminds you:

```sh
caddy trust    # one-time per machine
```

That installs the root into the system store, Firefox, and your host NSS db —
enough for Firefox and natively-packaged Chrome/Chromium.

> [!IMPORTANT]
> **Chrome installed via Flatpak won't see that root** — it's sandboxed away
> from the system store, so it needs a one-time manual import into Chrome's own
> cert store:
>
> 1. Copy the root where the sandbox can read it (it sees `~/Downloads`):
>    `cp ~/.local/share/caddy/pki/authorities/local/root.crt ~/Downloads/caddy-para-root.crt`
> 2. Visit `chrome://certificate-manager` → **Custom** → **Trusted
>    Certificates** → **Import** → pick it (not the read-only "operating
>    system" group).
> 3. Still erroring after reload? Stale HSTS, not trust:
>    `chrome://net-internals/#hsts` → delete the hostname's security policy,
>    reload.
