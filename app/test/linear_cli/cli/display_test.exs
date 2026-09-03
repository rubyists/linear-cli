defmodule LinearCli.CLI.DisplayTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias LinearCli.CLI.Display
  alias LinearCli.Linear.{Issue, Label}

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

  test "full issue output syntax-highlights fenced Ruby code through Syntect" do
    issue = %Issue{
      id: "issue-1",
      identifier: "EXT-1",
      title: "Highlight Ruby markdown",
      description: """
      ```ruby
      class Greeter
        def hello(name)
          puts "Hello!"
        end
      end
      ```
      """,
      comments: []
    }

    output = capture_io(fn -> Display.show(issue, %{full: true}) end)
    theme = Marcli.Theme.default()

    assert output =~ theme.syntax.keyword_type <> "class" <> theme.reset
    assert output =~ theme.syntax.name_class <> "Greeter" <> theme.reset
    assert output =~ theme.syntax.name_function <> "hello" <> theme.reset
    refute output =~ theme.code_text <> "class Greeter"
  end

  test "full issue output includes a Labels line when labels are present" do
    issue = %Issue{
      id: "issue-2",
      identifier: "EXT-2",
      title: "Labelled issue",
      description: "Some work",
      comments: [],
      labels: [
        %Label{id: "l1", name: "Bug", description: nil, is_group: false},
        %Label{id: "l2", name: "Feature", description: nil, is_group: false}
      ]
    }

    output = capture_io(fn -> Display.show(issue, %{full: true}) end)

    assert output =~ "Labels: Bug, Feature"
  end

  test "full issue output omits the Labels line when no labels are present" do
    issue = %Issue{
      id: "issue-3",
      identifier: "EXT-3",
      title: "Unlabelled issue",
      description: "Some work",
      comments: [],
      labels: []
    }

    output = capture_io(fn -> Display.show(issue, %{full: true}) end)

    refute output =~ "Labels:"
  end
end
