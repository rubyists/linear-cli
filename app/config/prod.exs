import Config

# LinearCli.ObanRepo's connection details live in config/runtime.exs, not
# here - a real deployment builds the release once and runs it against
# whatever database/credentials the target host has, which means those
# details must be resolved at boot, not baked in at build time. See that
# file and ObanRepo's moduledoc.
