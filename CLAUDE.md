# CLAUDE.md — Development Guidelines

## TDD (Test-Driven Development)

Always use the **superpowers:test-driven-development** skill when implementing any feature or bugfix.
Write tests first, then implement.

## Test Integrity

Tests define expected behavior. If a test fails, the implementation is wrong — not the test. Never
weaken, skip, or delete tests to make them pass. Fix the code instead.

## Documentation is Mandatory

Every feature or change must update **all** relevant docs before the work is considered complete:

- `README.md` — command reference and usage examples
- `docs/DEVELOPMENT.md` — architecture and internals
- `CONTRIBUTING.md` — contributor instructions
- Inline help text in `bin/wt` (the comment block at the top and any `wt help` output)

## Running Tests

```bash
bash bin/wt-test
```

All tests must pass before committing.
