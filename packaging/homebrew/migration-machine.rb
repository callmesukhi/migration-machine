class MigrationMachine < Formula
  desc "Move your Mac setup to a new machine without Migration Assistant"
  homepage "https://migration-machine.callmesukhi.com"
  url "https://github.com/callmesukhi/migration-machine/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "113e9f2eb0eea5c4cd50e76ff03a4d4ca5fe6c61802837968addc213a3237421"
  license "MIT"
  head "https://github.com/callmesukhi/migration-machine.git", branch: "main"

  depends_on :macos

  # No build step: this is plain bash. We stage the tool under libexec and put a
  # thin launcher on PATH so `migrate` resolves its own lib/, steps/, manifests/.
  def install
    libexec.install "migrate", "lib", "steps", "manifests", "docs"
    (bin/"migrate").write <<~SH
      #!/bin/bash
      exec /bin/bash "#{libexec}/migrate" "$@"
    SH
    chmod 0o755, bin/"migrate"
  end

  def caveats
    <<~EOS
      The guided GUI setup uses swiftDialog, which is a separate cask:
        brew install --cask swiftdialog

      Then start the wizard:
        migrate wizard
    EOS
  end

  test do
    assert_match "migration-machine", shell_output("#{bin}/migrate version")
  end
end
