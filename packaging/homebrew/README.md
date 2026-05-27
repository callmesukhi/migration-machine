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
   brew install callmesukhi/tap/migration-machine
   migrate wizard
   ```

## Releasing a new version

The formula pins a stable release via `url` + `sha256` (currently `v0.1.0`).
`--HEAD` is still available for installing the latest `main`:

```bash
brew install --HEAD callmesukhi/tap/migration-machine
```

To cut a new version, tag it, hash the tarball, bump the formula, and copy it
into the tap repo:

```bash
git tag vX.Y.Z && git push origin vX.Y.Z
curl -fsSL https://github.com/callmesukhi/migration-machine/archive/refs/tags/vX.Y.Z.tar.gz | shasum -a 256
# update `url` and `sha256` in migration-machine.rb, then copy it into homebrew-tap/Formula/
```

## Notes

- Homebrew formulae cannot declare a cask as a dependency, so swiftDialog is not
  auto-installed by `brew install`. The formula prints a caveat, and `migrate
  wizard` also offers to install swiftDialog at runtime.
- Once the tap is live, add the `brew install` line to the README and the site.
  It is intentionally left out until then so there is no broken copy-paste.
