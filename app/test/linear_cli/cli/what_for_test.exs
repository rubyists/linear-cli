defmodule LinearCli.CLI.WhatForTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureIO

  alias LinearCli.CLI.WhatFor
  alias LinearCli.Linear.{Issue, Label, Team}

  defp issue(attrs) do
    struct!(%Issue{id: "i1", identifier: "CRY-1", title: "Untitled"}, attrs)
  end

  describe "title_for/1 (Ruby: WhatFor#title_for)" do
    test "returns the given title unchanged, without prompting" do
      assert capture_io(fn -> assert WhatFor.title_for("Ship it") == "Ship it" end) == ""
    end

    test "prompts for a title when none is given" do
      assert capture_io([input: "Ship it\n"], fn ->
               assert WhatFor.title_for(nil) == "Ship it"
             end) =~ "Title:"
    end
  end

  describe "description_for/1, reason_for/2, comment_for/2 (thin ask_or_edit/3 wrappers)" do
    test "description_for/1 returns the given description unchanged, without prompting" do
      assert capture_io(fn ->
               assert WhatFor.description_for("Because reasons") == "Because reasons"
             end) == ""
    end

    test "description_for/1 asks when none is given" do
      assert capture_io([input: "Typed in\n"], fn ->
               assert WhatFor.description_for(nil) == "Typed in"
             end) =~ "Description: ('-' to open an editor)"
    end

    test "reason_for/2 asks with the bare 'Reason' question when :four is omitted" do
      assert capture_io([input: "Because\n"], fn ->
               assert WhatFor.reason_for(nil) == "Because"
             end) =~ "Reason: ('-' to open an editor)"
    end

    test "reason_for/2 folds :four into the question (interpolated as plain text, no markdown rendering)" do
      output =
        capture_io([input: "Because\n"], fn ->
          assert WhatFor.reason_for(nil, four: "cancelling CRY-1") == "Because"
        end)

      assert output =~ "Reason for cancelling CRY-1: ('-' to open an editor)"
    end

    test "comment_for/2 scopes the question to the issue" do
      output =
        capture_io([input: "lgtm\n"], fn ->
          assert WhatFor.comment_for(issue(identifier: "CRY-9", title: "Fix it"), nil) == "lgtm"
        end)

      assert output =~ "Comment for CRY-9 - Fix it: ('-' to open an editor)"
    end
  end

  describe "ask_or_edit/3 (Ruby: WhatFor#ask_or_edit)" do
    test "returns thing unchanged, without prompting, when it's given and isn't \"-\"" do
      assert capture_io(fn ->
               assert WhatFor.ask_or_edit("already here", "Question") == "already here"
             end) == ""
    end

    test "asks, and returns the answer, when thing is nil and the answer isn't \"-\"" do
      assert capture_io([input: "typed answer\n"], fn ->
               assert WhatFor.ask_or_edit(nil, "Question") == "typed answer"
             end) =~ "Question: ('-' to open an editor)"
    end

    test "opens an editor when the answer is \"-\" (the default on a blank line)" do
      assert capture_io([input: "\n"], fn ->
               assert WhatFor.ask_or_edit(nil, "Question", editor: "printf hello > __FILE__") ==
                        "hello"
             end) =~ "Question: ('-' to open an editor)"
    end

    test "opens an editor directly when thing is already \"-\", after still asking once" do
      assert capture_io([input: "\n"], fn ->
               assert WhatFor.ask_or_edit("-", "Question", editor: "printf hello > __FILE__") ==
                        "hello"
             end)
    end

    test "raises when the editor produced no content" do
      assert capture_io([input: "\n"], fn ->
               assert_raise RuntimeError, ~r/No content provided for Question/, fn ->
                 WhatFor.ask_or_edit(nil, "Question", editor: "true")
               end
             end)
    end
  end

  describe "editor_for/2 (Ruby: WhatFor#editor_for)" do
    test "returns a single edited line as-is" do
      assert WhatFor.editor_for(nil, editor: "printf hello > __FILE__") == "hello"
    end

    test "joins multiple lines with the literal two-character string \"\\n\" (backslash + n), not a real newline" do
      result =
        WhatFor.editor_for(nil, editor: "printf 'line1\\nline2\\n' > __FILE__")

      assert result == "line1\\nline2"
      refute result =~ "\n"
    end

    test "an empty editor buffer returns an empty string" do
      assert WhatFor.editor_for(nil, editor: "true") == ""
    end
  end

  describe "pr_type_for/1 (Ruby: WhatFor#pr_type_for) - pure regex-based inference, no prompting" do
    test "infers the type from a recognized, lowercase prefix" do
      assert capture_io(fn ->
               assert WhatFor.pr_type_for(issue(title: "fix: the thing")) == "fix"
             end) == ""
    end

    test "matches case-insensitively but always returns the type lowercased" do
      assert WhatFor.pr_type_for(issue(title: "FEAT: add the thing")) == "feat"
      assert WhatFor.pr_type_for(issue(title: "Chore: tidy up")) == "chore"
    end

    test "matches every configured PR type" do
      for {type, _description} <- [
            fix: nil,
            feat: nil,
            chore: nil,
            eyes: nil,
            test: nil,
            perf: nil,
            refactor: nil,
            docs: nil,
            sec: nil,
            style: nil,
            ci: nil,
            db: nil
          ] do
        assert WhatFor.pr_type_for(issue(title: "#{type}: something")) == to_string(type)
      end
    end

    test "prompts for a type when the title has no recognized prefix" do
      output =
        capture_io([input: "2\n"], fn ->
          assert WhatFor.pr_type_for(issue(title: "Just a plain title")) == "feat"
        end)

      assert output =~ "What type of PR is this?"
    end
  end

  describe "pr_scope_for/1 (Ruby: WhatFor#pr_scope_for) - pure regex extraction, no prompting" do
    test "extracts and downcases a leading type(scope)" do
      assert capture_io(fn ->
               assert WhatFor.pr_scope_for("fix(Auth): broken login") == "auth"
             end) == ""
    end

    test "prompts, and returns the typed answer, when there's no leading scope" do
      output =
        capture_io([input: "billing\n"], fn ->
          assert WhatFor.pr_scope_for("Just a plain title") == "billing"
        end)

      assert output =~ "What is the scope of this PR?"
    end

    test "a blank answer defaults to the literal string \"none\" - not nil (Ruby's own dead-code guard never fires)" do
      assert capture_io([input: "\n"], fn ->
               assert WhatFor.pr_scope_for("Just a plain title") == "none"
             end) =~ "What is the scope of this PR?"
    end
  end

  describe "pr_title_for/1 (Ruby: WhatFor#pr_title_for)" do
    test "proposes a title from a fully-prefixed issue title, with no scope/type prompts" do
      output =
        capture_io([input: "\n"], fn ->
          assert WhatFor.pr_title_for(issue(identifier: "CRY-1", title: "fix(auth) Login broken")) ==
                   "fix(auth): CRY-1 - Login broken"
        end)

      assert output =~ "Title for PR for CRY-1 - Login broken"
    end

    test "an explicit answer overrides the proposed default" do
      assert capture_io([input: "My own title\n"], fn ->
               assert WhatFor.pr_title_for(
                        issue(identifier: "CRY-1", title: "fix(auth) Login broken")
                      ) == "My own title"
             end)
    end

    test "falls back to prompting for both type and scope when the title has neither" do
      # "1\n" answers the type select (PR_TYPES' first entry, :fix); the
      # second "\n" answers pr_scope_for's ask with a blank line, which
      # (per its own dead-code guard, ported as-is) resolves to the literal
      # string "none" - truthy, so it's folded into the title as "(none)".
      # The third "\n" accepts the final proposed title as-is.
      output =
        capture_io([input: "1\n\n\n"], fn ->
          assert WhatFor.pr_title_for(issue(identifier: "CRY-2", title: "Untitled work")) ==
                   "fix(none): CRY-2 - Untitled work"
        end)

      assert output =~ "What type of PR is this?"
      assert output =~ "What is the scope of this PR?"
      assert output =~ "Title for PR for CRY-2 - Untitled work"
    end
  end

  describe "pr_description_for/2 (Ruby: WhatFor#pr_description_for)" do
    test "opens the Context/Issue/Solution/Testing/Notes template in an editor" do
      result =
        WhatFor.pr_description_for(
          issue(identifier: "CRY-3", description: "Some context"),
          editor: "printf '%s' \"$(cat __FILE__)-edited\" > __FILE__"
        )

      assert result =~ "# Context"
      assert result =~ "Some context"
      assert result =~ "## Issue"
      assert result =~ "CRY-3"
      assert result =~ "# Solution"
      assert result =~ "# Testing"
      assert result =~ "# Notes"
      assert result =~ "-edited"
    end
  end

  describe "team_for/1 (Ruby: WhatFor#team_for)" do
    test "looks the team up directly when a key is given, without prompting" do
      Req.Test.stub(LinearCli.Api, fn conn ->
        Req.Test.json(conn, %{
          "data" => %{
            "team" => %{
              "id" => "t1",
              "key" => "ENG",
              "name" => "Engineering",
              "description" => nil
            }
          }
        })
      end)

      assert capture_io(fn ->
               assert %Team{id: "t1", key: "ENG"} = WhatFor.team_for("ENG")
             end) == ""
    end

    test "raises when the given key doesn't resolve to any team" do
      Req.Test.stub(LinearCli.Api, fn conn ->
        Req.Test.json(conn, %{"data" => %{"team" => nil}})
      end)

      assert_raise RuntimeError, ~r/No team found with id nope/, fn ->
        WhatFor.team_for("nope")
      end
    end

    test "falls back to ask_for_team/0 when no key is given" do
      Req.Test.stub(LinearCli.Api, fn conn ->
        Req.Test.json(conn, %{
          "data" => %{
            "viewer" => %{
              "id" => "u1",
              "name" => "Ada",
              "email" => "ada@example.com",
              "teams" => %{"nodes" => [%{"id" => "t1", "key" => "ENG", "name" => "Engineering"}]}
            }
          }
        })
      end)

      assert capture_io(fn -> assert %Team{id: "t1"} = WhatFor.team_for(nil) end) == ""
    end
  end

  describe "ask_for_team/0 (Ruby: CLI::SubCommands#ask_for_team)" do
    test "returns the sole team directly, without prompting" do
      Req.Test.stub(LinearCli.Api, fn conn ->
        Req.Test.json(conn, %{
          "data" => %{
            "viewer" => %{
              "id" => "u1",
              "name" => "Ada",
              "email" => "ada@example.com",
              "teams" => %{"nodes" => [%{"id" => "t1", "key" => "ENG", "name" => "Engineering"}]}
            }
          }
        })
      end)

      assert capture_io(fn -> assert %Team{id: "t1"} = WhatFor.ask_for_team() end) == ""
    end

    test "prompts across every team when there's more than one" do
      Req.Test.stub(LinearCli.Api, fn conn ->
        Req.Test.json(conn, %{
          "data" => %{
            "viewer" => %{
              "id" => "u1",
              "name" => "Ada",
              "email" => "ada@example.com",
              "teams" => %{
                "nodes" => [
                  %{"id" => "t1", "key" => "ENG", "name" => "Engineering"},
                  %{"id" => "t2", "key" => "SUP", "name" => "Support"}
                ]
              }
            }
          }
        })
      end)

      output =
        capture_io([input: "2\n"], fn ->
          assert %Team{id: "t2"} = WhatFor.ask_for_team()
        end)

      assert output =~ "Choose a team"
    end

    test "raises when there are no teams" do
      Req.Test.stub(LinearCli.Api, fn conn ->
        Req.Test.json(conn, %{
          "data" => %{
            "viewer" => %{
              "id" => "u1",
              "name" => "Ada",
              "email" => "ada@example.com",
              "teams" => %{"nodes" => []}
            }
          }
        })
      end)

      assert_raise RuntimeError, ~r/No team given and none found for you/, fn ->
        WhatFor.ask_for_team()
      end
    end
  end

  describe "labels_for/2 (Ruby: WhatFor#labels_for)" do
    test "looks up labels by name when given, trimming whitespace, without prompting" do
      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        %{"variables" => %{"names" => names}} = Jason.decode!(body)
        assert names == ["bug", "urgent"]

        Req.Test.json(conn, %{
          "data" => %{
            "issueLabels" => %{
              "edges" => [
                %{
                  "node" => %{
                    "id" => "l1",
                    "name" => "bug",
                    "description" => nil,
                    "isGroup" => false
                  }
                },
                %{
                  "node" => %{
                    "id" => "l2",
                    "name" => "urgent",
                    "description" => nil,
                    "isGroup" => false
                  }
                }
              ]
            }
          }
        })
      end)

      team = %Team{id: "t1", key: "ENG"}

      assert capture_io(fn ->
               assert [%Label{name: "bug"}, %Label{name: "urgent"}] =
                        WhatFor.labels_for(team, [" bug ", "urgent"])
             end) == ""
    end

    test "prompts across the team's labels when none are given" do
      Req.Test.stub(LinearCli.Api, fn conn ->
        Req.Test.json(conn, %{
          "data" => %{
            "team" => %{
              "labels" => %{
                "nodes" => [
                  %{
                    "id" => "l1",
                    "name" => "bug",
                    "description" => nil,
                    "isGroup" => false,
                    "parent" => nil
                  },
                  %{
                    "id" => "l2",
                    "name" => "urgent",
                    "description" => nil,
                    "isGroup" => false,
                    "parent" => nil
                  }
                ]
              }
            }
          }
        })
      end)

      team = %Team{id: "t1", key: "ENG"}

      output =
        capture_io([input: "1 2\n"], fn ->
          assert [%Label{name: "bug"}, %Label{name: "urgent"}] = WhatFor.labels_for(team, nil)
        end)

      assert output =~ "Labels:"
    end
  end
end
