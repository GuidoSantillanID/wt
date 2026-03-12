# Contributing

## Running Tests

```bash
bash bin/wt-test
```

Tests require bash 4+ (macOS ships with bash 3.2 — install via `brew install bash`). CI runs on both macOS and Linux.

## Making Changes

- Keep changes focused — one concern per PR
- All tests must pass before submitting
- Follow the existing shell style (`set -euo pipefail`, quoted variables, no `eval`)

## Reporting Issues

Open an issue at https://github.com/GuidoSantillanID/wt/issues with steps to reproduce.
