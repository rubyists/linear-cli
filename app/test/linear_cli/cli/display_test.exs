defmodule LinearCli.CLI.DisplayTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias LinearCli.CLI.Display
  alias LinearCli.Linear.Issue

  test "full issue output syntax-highlights fenced Elixir code" do
    issue = %Issue{
      id: "issue-1",
      identifier: "EXT-1",
      title: "Highlight markdown",
      description: """
      ```elixir
      defmodule Example do
        def answer, do: 42
      end
      ```
      """,
      comments: []
    }

    output = capture_io(fn -> Display.show(issue, %{full: true}) end)
    theme = Marcli.Theme.default()

    assert output =~ theme.syntax.keyword_declaration <> "defmodule" <> theme.reset
    assert output =~ theme.syntax.name_class <> "Example" <> theme.reset
    assert output =~ theme.syntax.number <> "42" <> theme.reset
    refute output =~ theme.code_text <> "defmodule"
  end
end
