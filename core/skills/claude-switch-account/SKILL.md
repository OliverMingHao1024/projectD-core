---
name: claude-switch-account
description: Safely inspect and switch the active Claude Code subscription account through official auth commands, with alias resolution, subscription-only billing checks, and post-login identity verification. Use when the user asks which Claude account is active, asks to switch Claude to work, personal, or 個人, wants to change Claude accounts, or needs to verify Claude is not using API billing.
---

# Claude Switch Account

Use only Claude Code's official interactive authentication flow. Keep account aliases
in the Git-ignored local profile file; never put personal email addresses in this Skill.

## Inspect status

Locate the local profile file, normally
`.local/governance/claude-account-profiles.json` under `projectD-core`, then run:

```powershell
& scripts/claude-account.ps1 -Action Status
```

Status is read-only. Report the sanitized account identity and every blocker. Do not
continue when the result fails its subscription-only checks.

## Prepare a switch

Resolve the requested alias without changing authentication:

```powershell
& scripts/claude-account.ps1 `
  -Action Prepare `
  -Target "personal" `
  -ProfilesPath "<projectD-core>/.local/governance/claude-account-profiles.json"
```

Treat `work`, `personal`, `工作`, and `個人` as local aliases only. Use the profile
file as the source of truth. If the target is already active, stop successfully.

## Switch only after confirmation

When `ready_to_switch` is true, state the current and target aliases and ask for
fresh explicit confirmation. Explain that the action signs out the current Claude
session and opens the official interactive login. Do not reuse confirmation from an
earlier turn.

After confirmation, run these commands interactively, in order:

```powershell
claude auth logout
claude auth login
```

Let the user complete Claude's official browser login. Never choose an account on
the user's behalf. Never loop, rotate, or switch automatically because of usage
limits.

## Verify the result

Immediately verify the selected target:

```powershell
& scripts/claude-account.ps1 `
  -Action Verify `
  -Target "personal" `
  -ProfilesPath "<projectD-core>/.local/governance/claude-account-profiles.json"
```

Require the active email to match the target exactly. If verification fails, stop
and report the blocker; do not retry logout or login automatically.

## Enforce safety

- Require `authMethod` to be `claude.ai`, `apiProvider` to be `firstParty`, and a
  subscription type to be present.
- Reject API billing credentials and Bedrock, Vertex, or Foundry routing.
- Never read, copy, print, move, back up, or store `.credentials.json`, OAuth
  values, setup tokens, API keys, passwords, or operating-system credential-store
  entries.
- Store only aliases and email addresses in the local profile file. Keep it ignored
  by Git.
- Treat status and preparation as read-only Sources. Treat logout and login as
  external Actions that always require fresh confirmation.
