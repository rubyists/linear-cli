defmodule LinearCli.CLI.Commands.System do
  @moduledoc """
  Top-level system commands: whoami and version.
  Ported from vendor/ruby-linear-cli/lib/linear/commands/.
  """

  alias LinearCli.CLI.Display
  alias LinearCli.Linear

  @doc "Ported from commands/whoami.rb."
  def whoami(%{flags: flags, options: options}) do
    with {:ok, user} <- Linear.me() do
      Display.show(user, %{output: options.output, teams: flags.teams})
      :ok
    end
  end

  @doc """
  Ported from commands/version.rb, extended to respect the global
  `--output json` option like every other command does - previously
  ignored it and always printed plain text. The hidden Markdown renders make
  this command a complete release smoke test for the MDEx and Syntect NIFs,
  Marcli's syntax-highlighting integration, and the application boot path.
  """
  def version(%{options: options}) do
    verify_markdown_runtime!()
    version = to_string(Application.spec(:linear_cli, :vsn))

    if options.output == "json" do
      IO.puts(Jason.encode!(%{version: version}))
    else
      IO.puts(version)
    end

    :ok
  end

  defp verify_markdown_runtime! do
    theme = Marcli.Theme.default()
    elixir = Marcli.render("```elixir\ndef smoke, do: :ok\n```")
    ruby = Marcli.render("```ruby\ndef smoke; :ok; end\n```")

    elixir_keyword = theme.syntax.keyword_declaration <> "def" <> theme.reset
    ruby_keyword = theme.syntax.keyword_type <> "def" <> theme.reset

    unless String.contains?(elixir, elixir_keyword) and String.contains?(ruby, ruby_keyword) do
      raise "Markdown syntax-highlighting runtime is unavailable"
    end

    :ok
  end
end
