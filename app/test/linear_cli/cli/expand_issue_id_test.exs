defmodule LinearCli.CLI.ExpandIssueIdTest do
  # Not async: shares LinearCli.Profiles/LinearCli.Favorites' one sqlite
  # file (config :linear_cli, :profiles_db_path) - see
  # LinearCli.CLI.ProfileDefaultsTest's own comment for why this is safe.
  use ExUnit.Case, async: false
  import ExUnit.CaptureIO

  alias LinearCli.CLI.IssueHelpers
  alias LinearCli.{Favorites, Profiles}

  setup do
    path = Application.fetch_env!(:linear_cli, :profiles_db_path)
    File.rm(path)
    :ok
  end

  defp teams_response(teams) do
    %{
      "data" => %{
        "viewer" => %{
          "id" => "u1",
          "name" => "Ada",
          "email" => "ada@example.com",
          "teams" => %{"nodes" => teams}
        }
      }
    }
  end

  describe "expand_issue_id/1 (Phase 11: bare issue numbers)" do
    test "a bare number resolves via the active profile's team, without prompting" do
      {:ok, _} = Profiles.create("manhattan", team: "CRY")
      :ok = Profiles.activate("manhattan")

      assert capture_io(fn ->
               assert IssueHelpers.expand_issue_id("1234") == "CRY-1234"
             end) == ""
    end

    test "with no active profile but one favorited team, uses it directly, without prompting" do
      Favorites.add("team", "ENG")

      assert capture_io(fn ->
               assert IssueHelpers.expand_issue_id("42") == "ENG-42"
             end) == ""
    end

    test "with no active profile and several favorited teams, prompts and uses the selected one" do
      Favorites.add("team", "ENG")
      Favorites.add("team", "SUP")

      output =
        capture_io([input: "2\n"], fn ->
          assert IssueHelpers.expand_issue_id("42") == "SUP-42"
        end)

      assert output =~ "Choose a team"
    end

    test "with no profile and no favorites, falls through to ask_for_team/0's own full prompt" do
      Req.Test.stub(LinearCli.Api, fn conn ->
        Req.Test.json(
          conn,
          teams_response([
            %{"id" => "t1", "key" => "ENG", "name" => "Engineering"},
            %{"id" => "t2", "key" => "SUP", "name" => "Support"}
          ])
        )
      end)

      output =
        capture_io([input: "2\n"], fn ->
          assert IssueHelpers.expand_issue_id("42") == "SUP-42"
        end)

      assert output =~ "Choose a team"
    end

    test "an already-prefixed id and a UUID pass through unchanged, regardless of profile/favorites" do
      {:ok, _} = Profiles.create("manhattan", team: "CRY")
      :ok = Profiles.activate("manhattan")
      Favorites.add("team", "ENG")

      assert capture_io(fn ->
               assert IssueHelpers.expand_issue_id("CRY-1234") == "CRY-1234"

               assert IssueHelpers.expand_issue_id("550e8400-e29b-41d4-a716-446655440000") ==
                        "550e8400-e29b-41d4-a716-446655440000"
             end) == ""
    end
  end
end
