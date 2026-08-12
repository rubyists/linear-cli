#!/usr/bin/env ruby
# Bumps a Homebrew formula's per-platform `url`/`sha256` pairs to a new
# rubyists/linear-cli release - the `.github/workflows/main.yaml`
# `homebrew-tap-bump` job's only real logic, kept out of the workflow YAML
# so it's runnable/testable locally without a real CI run.
#
# Usage: bump_homebrew_formula.rb FORMULA_PATH TAG SHA256SUMS_PATH
#
#   FORMULA_PATH     path to the formula file (e.g. Formula/linear-cli/linear-cli.rb)
#   TAG              the release tag, e.g. "v1.3.0"
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

content = File.read(formula_path)

%w[macos_aarch64 linux_x86_64].each do |target|
  asset = "lc_#{target}.tar.gz"
  sha = sha256sums.fetch(asset) { abort "No checksum found for #{asset} in #{sha256sums_path}" }

  pattern = /
    url\ "https:\/\/github\.com\/rubyists\/linear-cli\/releases\/download\/v[\d.]+\/#{Regexp.escape(asset)}"
    \n(\s*)
    sha256\ "[a-f0-9]+"
  /x

  unless content.match?(pattern)
    abort "Could not find a url/sha256 pair for #{asset} in #{formula_path}"
  end

  content = content.sub(pattern) do
    indent = ::Regexp.last_match(1)
    %(url "https://github.com/rubyists/linear-cli/releases/download/#{tag}/#{asset}"\n#{indent}sha256 "#{sha}")
  end
end

File.write(formula_path, content)
puts "Bumped #{formula_path} to #{tag}"
