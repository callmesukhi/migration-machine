# Homebrew distribution

`migration-machine.rb` is the formula. Homebrew installs it from a **tap**, which
is just a GitHub repo named `homebrew-<something>`. Publishing it is a one-time
setup you do on GitHub; this folder holds the source of truth.

## Publish the tap (one time)

1. Create a public repo named `homebrew-tap` under your account:
   `https://github.com/callmesukhi/homebrew-tap`
2. Add the formula to it:

   ```bash
   git clone https://github.com/callmesukhi/homebrew-tap.git
   mkdir -p homebrew-tap/Formula
   cp packaging/homebrew/migration-machine.rb homebrew-tap/Formula/
   cd homebrew-tap && git add Formula/migration-machine.rb && git commit -m "Add migration-machine" && git push
   ```

3. Users then install with:

   ```bash
   brew install --HEAD callmesukhi/tap/migration-machine
   migrate wizard
   ```

## Stable release vs. HEAD

The committed formula is HEAD-only: it has no stable `url`/`sha256` yet, so it
installs from the latest `main` with `--HEAD` (as shown above). To offer a
stable, versioned install, tag a release and add a stable block to the formula:

```bash
git tag v0.1.0 && git push --tags
curl -fsSL https://github.com/callmesukhi/migration-machine/archive/refs/tags/v0.1.0.tar.gz | shasum -a 256
# Add `url` + `sha256` lines to migration-machine.rb (a template is in the
# formula's comments). Then users can drop the --HEAD flag.
```

## Notes

- Homebrew formulae cannot declare a cask as a dependency, so swiftDialog is not
  auto-installed by `brew install`. The formula prints a caveat, and `migrate
  wizard` also offers to install swiftDialog at runtime.
- Once the tap is live, add the `brew install` line to the README and the site.
  It is intentionally left out until then so there is no broken copy-paste.
