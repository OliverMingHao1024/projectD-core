# chouten-court DevSpace Isolation

Second, independent instance of the isolation framework in
`containers/devspace-isolation/` (that one's README has the full
architecture explanation, network topology diagram, and "what rootless
means here" caveats -- not repeated here). This instance is bound to
`D:/workspaces/chouten-court` instead of `projectD-core`.

## Why a separate instance instead of switching the existing one

ADR 0015's single-bind-mount boundary means one running container can only
ever see one repo. Running a *second, fully independent* stack -- separate
containers, separate networks, separate squid instance, separate config
volume -- lets both projects be available to their own DevSpace connection
at the same time without either one being able to reach the other's
filesystem, credentials, or network path. Switching `DEVSPACE_REPO_PATH` on
the single existing instance would work too, but only one project would be
reachable at a time.

## What's different from the projectD-core instance

Only what has to differ to let both run concurrently on the same machine
without colliding:

- `container_name`s are prefixed `chouten-court-*` (Docker container names
  are global to the engine, unlike compose network names, which already get
  a project-specific prefix automatically).
- `port-forward` publishes `127.0.0.1:7677` instead of `7676`.
- `.env`'s `DEVSPACE_REPO_PATH` points at `D:/workspaces/chouten-court`, and
  `DEVSPACE_OAUTH_OWNER_TOKEN` is its own independently generated secret --
  never reuse the projectD-core instance's token here.

Everything else (non-root UID, `cap_drop: [ALL]` on every service including
`egress-proxy` via `user: "13:13"`, `read_only` root filesystems,
`no-new-privileges`, the deny-by-default squid allowlist plus the
private/loopback/link-local `dst` deny rule, `pinger_enable off`) is
identical to the projectD-core instance and carries the same verification
evidence recorded in
`docs/specs/devspace-isolation-container-framework.md`.

## Usage

```bash
cp .env.example .env
# edit .env: DEVSPACE_REPO_PATH is already set to chouten-court's path;
# generate DEVSPACE_OAUTH_OWNER_TOKEN with e.g. `openssl rand -base64 32`
docker compose up -d --build
```

DevSpace is then listening on `http://127.0.0.1:7677/mcp` on the host --
note the port, not `7676` (that's the projectD-core instance). Verify:

```powershell
pwsh -File scripts/verify-isolation.ps1
```

## Exposing this instance publicly (shared devtunnel)

This deployment reuses the same Microsoft Dev Tunnel
(`devspace-projectd`) the projectD-core instance already uses, adding a
second forwarded port rather than standing up a whole second tunnel process
and scheduled task -- one tunnel, two ports, less to keep alive:

```bash
devtunnel port create devspace-projectd -p 7677 --protocol http
devtunnel access create devspace-projectd -p 7677 --anonymous
```

No new tunnel process or scheduled task needed, but the **already-running**
`devtunnel host devspace-projectd` process does NOT pick up a newly added
port on its own -- confirmed by testing: after `port create`/`access
create` above, the existing host process kept only forwarding `7676` until
it was killed and restarted (`devtunnel host devspace-projectd` again, same
tunnel ID). If that process runs via the scheduled task
(`containers/devspace-isolation/README.md`'s "Exposing DevSpace publicly"
section), stop and restart the task (or kill the `devtunnel.exe` process and
let the task's `ONLOGON` trigger relaunch it, or just rerun the `host`
command manually) any time a port is added to or removed from the tunnel.
The resulting public URL is `https://<same-id>-7677.<region>.devtunnels.ms`;
put that in this instance's own `.env`'s `DEVSPACE_PUBLIC_BASE_URL`
(**not** the projectD-core instance's `.env`) and restart this stack.

The anonymous-access exception this relies on
(`docs/adr/0017-allow-anonymous-devtunnel-for-isolated-devspace-on-personal-registrations.md`)
is scoped to the tunnel/registration, not to a specific port -- adding a
port to an already-anonymous tunnel does not need a new exception.

## Cross-reference

Both instances share `scripts/governance-command-policy-hook.ps1` and
`vault/governance/project-classification.json` at the repo root -- those
govern which repositories/machines may invoke DevSpace tools at all, and
apply the same way regardless of which isolated instance is involved.
