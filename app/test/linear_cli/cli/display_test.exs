defmodule LinearCli.CLI.DisplayTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias LinearCli.CLI.Display
  alias LinearCli.Linear.{Issue, IssueRelation, Label}

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

  test "compact listing appends labels in brackets when labels opt is true" do
    issue = %Issue{
      id: "issue-4",
      identifier: "EXT-4",
      title: "Labelled compact",
      description: nil,
      comments: [],
      labels: [
        %Label{id: "l1", name: "Bug", description: nil, is_group: false},
        %Label{id: "l2", name: "Feature", description: nil, is_group: false}
      ]
    }

    output = capture_io(fn -> Display.show(issue, %{labels: true}) end)

    assert output =~ "EXT-4"
    assert output =~ "[Bug, Feature]"
  end

  test "compact listing omits label brackets when labels opt is false" do
    issue = %Issue{
      id: "issue-5",
      identifier: "EXT-5",
      title: "Unlabelled compact",
      description: nil,
      comments: [],
      labels: [
        %Label{id: "l1", name: "Bug", description: nil, is_group: false}
      ]
    }

    output = capture_io(fn -> Display.show(issue, %{labels: false}) end)

    assert output =~ "EXT-5"
    refute output =~ "[Bug]"
  end

  defp relation(id, type, direction, src_ident, rel_ident) do
    %IssueRelation{
      id: id,
      type: type,
      direction: direction,
      issue: %{
        id: "i-src",
        identifier: src_ident,
        title: "#{src_ident} Title",
        url: "https://example.com/#{src_ident}"
      },
      related_issue: %{
        id: "i-rel",
        identifier: rel_ident,
        title: "#{rel_ident} Title",
        url: "https://example.com/#{rel_ident}"
      }
    }
  end

  test "relations list shows Blocks section for outbound blocks relations" do
    rels = [relation("r1", "blocks", :outbound, "EXT-1", "EXT-2")]
    output = capture_io(fn -> Display.show(rels, %{}) end)

    assert output =~ "Blocks:"
    assert output =~ "EXT-2"
    refute output =~ "Blocked by:"
  end

  test "relations list shows Blocked by section for inbound blocks relations" do
    rels = [relation("r1", "blocks", :inbound, "EXT-3", "EXT-1")]
    output = capture_io(fn -> Display.show(rels, %{}) end)

    assert output =~ "Blocked by:"
    assert output =~ "EXT-3"
    refute output =~ "Blocks:"
  end

  test "relations list shows Related to section for related type" do
    rels = [relation("r1", "related", :outbound, "EXT-1", "EXT-4")]
    output = capture_io(fn -> Display.show(rels, %{}) end)

    assert output =~ "Related to:"
    assert output =~ "EXT-4"
  end

  test "relations list shows all relation sections in order" do
    rels = [
      relation("r1", "blocks", :outbound, "EXT-1", "EXT-2"),
      relation("r2", "blocks", :inbound, "EXT-3", "EXT-1"),
      relation("r3", "related", :outbound, "EXT-1", "EXT-4"),
      relation("r4", "duplicate", :outbound, "EXT-1", "EXT-5"),
      relation("r5", "similar", :outbound, "EXT-1", "EXT-6")
    ]

    output = capture_io(fn -> Display.show(rels, %{}) end)

    assert output =~ "Blocks:"
    assert output =~ "Blocked by:"
    assert output =~ "Related to:"
    assert output =~ "Duplicate of:"
    assert output =~ "Similar to:"
    assert String.contains?(output, "EXT-2")
    assert String.contains?(output, "EXT-3")
    assert String.contains?(output, "EXT-4")
    assert String.contains?(output, "EXT-5")
    assert String.contains?(output, "EXT-6")
  end

  test "full issue view shows relations when issue has them" do
    rel = relation("r1", "blocks", :outbound, "EXT-1", "EXT-2")

    issue = %Issue{
      id: "issue-1",
      identifier: "EXT-1",
      title: "Blocker issue",
      description: "This issue blocks another",
      comments: [],
      relations: [rel],
      inverse_relations: []
    }

    output = capture_io(fn -> Display.show(issue, %{full: true}) end)

    assert output =~ "Blocks:"
    assert output =~ "EXT-2"
  end

  test "full issue view omits relations block when issue has none" do
    issue = %Issue{
      id: "issue-1",
      identifier: "EXT-1",
      title: "Standalone issue",
      description: "No relations",
      comments: [],
      relations: [],
      inverse_relations: []
    }

    output = capture_io(fn -> Display.show(issue, %{full: true}) end)

    refute output =~ "Blocks:"
    refute output =~ "Related to:"
  end

  test "relations JSON output includes direction and type fields" do
    rels = [relation("r1", "blocks", :outbound, "EXT-1", "EXT-2")]
    output = capture_io(fn -> Display.show(rels, %{output: "json"}) end)

    decoded = Jason.decode!(output)
    assert is_list(decoded)
    [entry] = decoded
    assert entry["type"] == "blocks"
    assert entry["direction"] == "outbound"
    assert entry["id"] == "r1"
  end

  test "compact listing omits label brackets when issue has no labels even if labels opt is true" do
    issue = %Issue{
      id: "issue-6",
      identifier: "EXT-6",
      title: "No labels",
      description: nil,
      comments: [],
      labels: []
    }

    output = capture_io(fn -> Display.show(issue, %{labels: true}) end)

    assert output =~ "EXT-6"
    refute output =~ "["
  end
end
