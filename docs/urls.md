# Workspace URLs

Out of the box, a workspace named `my-feature` is served at
`https://my-feature.paraspace.dev:8443`, with no DNS setup, no privileged ports
and no configuration. Three things you may want to change:

- the certificate has to be [trusted once](#trusting-the-certificate);
- the **`:8443`** can [go away](#removing-the-port);
- **`paraspace.dev`** can be [your own domain](#using-your-own-domain).

## Trusting the certificate

`para`'s Caddy issues each workspace a certificate from its own local CA, so
browsers distrust them until that CA's root is in your trust store.

**Usually this is already done.** Caddy tries to install its root the first
time it needs one, prompting for your password. On macOS that lands in the
system keychain, and you may never think about it again. If Caddy couldn't (it
was running unprivileged, or you dismissed the prompt), install it by hand:

```sh
caddy trust    # once per machine
```

That covers the system store, Firefox, and your host NSS db, enough for
Firefox and natively-packaged Chrome/Chromium.

This is the main reason `para`'s Caddy runs on the **host** rather than inside
a workspace. One CA, trusted once, and every workspace you ever create gets a
certificate your browser already accepts. A per-workspace proxy would mean a
new root to trust each time.

> [!IMPORTANT]
> **Chrome installed via Flatpak won't see that root.** It's sandboxed away
> from the system store, so it needs a one-time manual import into Chrome's own
> cert store:
>
> 1. Copy the root where the sandbox can read it (it sees `~/Downloads`):
>    `cp ~/.local/share/caddy/pki/authorities/local/root.crt ~/Downloads/caddy-para-root.crt`
> 2. Visit `chrome://certificate-manager` → **Custom** → **Trusted
>    Certificates** → **Import** → pick it (not the read-only "operating
>    system" group).
> 3. If it still errors after a reload, that's stale HSTS rather than trust.
>    Open `chrome://net-internals/#hsts`, delete the hostname's security
>    policy, and reload.

## Removing the port

`para`'s Caddy binds `:8443` by default because any user can. For clean,
port-less URLs (`https://my-feature.paraspace.dev`), move it to `:443` in your
[user config](./parafile.md#user-config-not-parafile):

```sh
para config edit    # uncomment: : "${PARA_HTTPS_PORT:=443}"
```

On Linux, non-root can't bind ports below 1024, so also grant the caddy binary
the bind capability, and re-apply it after every `caddy` upgrade:

```sh
sudo setcap cap_net_bind_service=+ep "$(readlink -f "$(command -v caddy)")"
```

macOS allows the bind as-is, so the config change alone is enough. Then
`para caddy start`. `para doctor` checks the capability and prints the exact
command if it's missing.

## Using your own domain

Workspaces resolve at `<name>.$PARA_DOMAIN`. The default `paraspace.dev`
wildcards to `127.0.0.1`, which is why it works with zero setup. To serve under
your own domain instead:

1. Point a wildcard `*.<your-domain> → 127.0.0.1` in your DNS.
2. Set `PARA_DOMAIN` in the project's `Parafile`, or in your user config if
   it's a personal domain you want across every project.

`para doctor` checks that the wildcard actually resolves to `127.0.0.1`, which
is the most common reason a workspace comes up but its URL doesn't load.
