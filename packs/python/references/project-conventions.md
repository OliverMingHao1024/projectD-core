# Python Project Conventions

Read this reference when the task changes project structure, typing, tests, or tool commands.

## Project Structure

- Keep one-off automation as a single script only while it remains cohesive. Split growing
  tools into an entry point and focused modules.
- Keep business logic outside FastAPI routers, Flask views, and Django views.
- Convert notebook work that must be reviewed or reproduced into deterministic functions
  or scripts; do not rely on cell execution order as the final artifact.

## Types and Quality Tools

- Add type annotations at public module, service, and API boundaries.
- Inspect `pyproject.toml`, `mypy.ini`, Ruff, Black, and other existing configuration before
  selecting commands or changing formatting.
- Preserve the project's package manager and lockfile workflow: pip, Poetry, uv, or another
  established tool.

## Review Checklist

- Preserve useful exception context and avoid bare or silently swallowed exceptions.
- Validate web and external input with the framework's established boundary models.
- Check data volume before loading entire datasets into memory.
- Keep secrets and machine-specific paths out of source.
- Give loops, retries, and recursion explicit termination conditions.

## Tests and Commands

- Use the existing test framework. Prefer pytest only when the repository has no established
  alternative and adding it is within scope.
- Name pytest files `test_*.py` and mirror the production module structure.
- Use framework test clients instead of real network calls for web unit tests.
- Run commands through the repository's selected environment and package manager rather
  than assuming global `pip` or `python`.
