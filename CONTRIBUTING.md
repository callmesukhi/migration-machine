# Contributing

Thanks for considering a contribution. This project values small, readable, well-tested shell.

## Ground rules

- Target macOS `bash` 3.2 (the system bash). No associative arrays, no `mapfile`, no `${var,,}`.
- Keep step scripts idempotent and safe to re-run.
- Prefer a manifest `validation` over re-checking state inside a step.
- Stream meaningful output so the user (and the log) can see what happened.
- Never commit captured data or secrets. The `.gitignore` covers the data dirs and `local-*.json` manifests.

## Adding a step

1. Write `steps/<name>.sh`. It receives `MIGRATE_ROOT`, `MIGRATION_DATA`, `KIT_DIR`, `STEP_ID`, and all `CFG_*`. See [docs/MANIFEST.md](docs/MANIFEST.md) for the contract.
2. Make it return non-zero only on real failure.
3. Add an entry to the relevant manifest(s) with a `validation` that proves success.

## Testing

Before opening a PR:

```bash
# syntax-check everything
for f in migrate lib/*.sh steps/*.sh; do bash -n "$f" || echo "BAD $f"; done

# validate manifests
for j in manifests/*.json; do python3 -c "import json,sys;json.load(open('$j'))" || echo "BAD $j"; done

# shellcheck if you have it
shellcheck migrate lib/*.sh steps/*.sh

# a dry run changes nothing and exercises the engine
./migrate --data /tmp/md provision -m example-homebrew --dry-run --ui cli
```

The engine's control flow (validation skip/confirm, required vs optional, dry-run, `--only`) is the part most worth testing. You can verify it on any Linux or macOS box with fake step scripts.

## Commit and PR

- One logical change per PR.
- Update `CHANGELOG.md` under `[Unreleased]`.
- Describe what you ran to test it.
