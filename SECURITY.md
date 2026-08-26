# Security Policy

This repository is a private, personally maintained AI governance knowledge
base (not a deployed service or published package). There is no supported
version matrix — only the current `master` state is maintained.

## Reporting a Vulnerability or Sensitive Issue

If you find a security issue (e.g. a leaked credential, an unsafe governance
rule, or a script that could execute untrusted input unsafely), report it
privately rather than opening a public issue:

- Contact: oliverminghao@gmail.com

Please include what you found, where (file/path/commit), and any reproduction
steps. Do not include live credentials in the report itself — note their
location instead so they can be rotated.

## Scope

In scope: governance rules, scripts under `scripts/`, CI workflows under
`.github/workflows/`, and any committed configuration that could leak secrets
or weaken repo integrity.

Out of scope: this repository has no runtime service, no dependency graph to
scan for CVEs, and no production deployment.
