#!/usr/bin/env ruby
# Bumps a Homebrew formula to a new rubyists/linear-cli release: writes
# `.version` (the formula's own single source of truth - it interpolates
# `#{version}` into each `url` itself, see the formula file, so the url
# lines never need touching here) and updates each platform's `sha256`.
# The `.github/workflows/main.yaml` `homebrew-tap-bump` job's only real
# logic, kept out of the workflow YAML so it's runnable/testable locally
# without a real CI run.
#
# Usage: bump_homebrew_formula.rb FORMULA_PATH TAG SHA256SUMS_PATH
#
#   FORMULA_PATH     path to the formula file (e.g. Formula/linear-cli/linear-cli.rb)
#   TAG              the release tag, e.g. "v1.4.0"
#   SHA256SUMS_PATH  that release's own SHA256SUMS asset, as downloaded

formula_path, tag, sha256sums_path = ARGV

unless formula_path && tag && sha256sums_path
  abort "Usage: #{$PROGRAM_NAME} FORMULA_PATH TAG SHA256SUMS_PATH"
end

sha256sums =
  File.readlines(sha256sums_path).each_with_object({}) do |line, acc|
    sha, name = line.split(/\s+/, 2)
    acc[name.strip] = sha if name
  end

version = tag.delete_prefix("v")
version_file = File.join(File.dirname(formula_path), ".version")
File.write(version_file, "#{version}\n")

content = File.read(formula_path)

%w[macos_aarch64 linux_x86_64].each do |target|
  asset = "lc_#{target}.tar.gz"
  sha = sha256sums.fetch(asset) { abort "No checksum found for #{asset} in #{sha256sums_path}" }

  # The url line is a constant - it always reads v#{version}/<asset>
  # verbatim in the formula's own source, never a literal version - only
  # the sha256 that follows it actually changes per release.
  pattern = /
    (url\ "https:\/\/github\.com\/rubyists\/linear-cli\/releases\/download\/v\#\{version\}\/#{Regexp.escape(asset)}"
    \n\s*sha256\ ")[a-f0-9]+(")
  /x

  unless content.match?(pattern)
    abort "Could not find a url/sha256 pair for #{asset} in #{formula_path}"
  end

  content = content.sub(pattern, "\\1#{sha}\\2")
end

File.write(formula_path, content)
puts "Wrote #{version_file} (#{version}) and updated #{formula_path}'s sha256 pairs to match"
