defmodule LinearCli.CLI.PromptTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureIO

  alias LinearCli.CLI.Prompt

  describe "ok/1" do
    test "prints the message in green" do
      assert capture_io(fn -> Prompt.ok("All good") end) == "\e[32mAll good\e[39m\e[0m\n"
    end
  end

  describe "warn/1" do
    test "prints the message in yellow" do
      assert capture_io(fn -> Prompt.warn("Careful now") end) ==
               "\e[33mCareful now\e[39m\e[0m\n"
    end
  end

  describe "say/1" do
    test "prints the message with no color" do
      assert capture_io(fn -> Prompt.say("Just so you know") end) == "Just so you know\n"
    end
  end

  describe "ask/2" do
    test "returns the typed answer when non-blank" do
      assert capture_io([input: "Ada Lovelace\n"], fn ->
               assert Prompt.ask("Name") == "Ada Lovelace"
             end) =~ "Name"
    end

    test "returns the given default when the answer is blank" do
      assert capture_io([input: "\n"], fn ->
               assert Prompt.ask("Title", default: "untitled") == "untitled"
             end) =~ "Title"
    end

    test "returns nil when the answer is blank and no default is given" do
      assert capture_io([input: "\n"], fn ->
               assert Prompt.ask("Title") == nil
             end) =~ "Title"
    end

    test "an explicit answer wins over a default" do
      assert capture_io([input: "Real Title\n"], fn ->
               assert Prompt.ask("Title", default: "untitled") == "Real Title"
             end) =~ "Title"
    end
  end

  describe "yes?/1" do
    test "defaults to true (yes) on a blank answer, unlike Owl.IO.confirm/1's own default" do
      assert capture_io([input: "\n"], fn ->
               assert Prompt.yes?("Continue?")
             end) =~ "[Yn]"
    end

    test "an explicit y answers true" do
      assert capture_io([input: "y\n"], fn ->
               assert Prompt.yes?("Continue?")
             end)
    end

    test "an explicit n answers false" do
      assert capture_io([input: "n\n"], fn ->
               refute Prompt.yes?("Continue?")
             end)
    end
  end

  describe "select/2" do
    test "returns the value paired with the chosen label" do
      choices = [{"Bug fixes", :fix}, {"New feature work", :feat}]

      output =
        capture_io([input: "2\n"], fn ->
          assert Prompt.select("What type of PR is this?", choices) == :feat
        end)

      assert output =~ "What type of PR is this?"
      assert output =~ "Bug fixes"
      assert output =~ "New feature work"
    end

    test "picking the first choice returns its value" do
      choices = [{"Bug fixes", :fix}, {"New feature work", :feat}]

      assert capture_io([input: "1\n"], fn ->
               assert Prompt.select("Pick", choices) == :fix
             end)
    end
  end

  describe "multi_select/2" do
    test "returns the values paired with every chosen label, in list order" do
      choices = [{"urgent", :urgent}, {"bug", :bug}, {"chore", :chore}]

      output =
        capture_io([input: "1 3\n"], fn ->
          assert Prompt.multi_select("Labels:", choices) == [:urgent, :chore]
        end)

      assert output =~ "Labels:"
      assert output =~ "urgent"
      assert output =~ "bug"
      assert output =~ "chore"
    end

    test "a blank answer selects nothing" do
      choices = [{"urgent", :urgent}, {"bug", :bug}]

      assert capture_io([input: "\n"], fn ->
               assert Prompt.multi_select("Labels:", choices) == []
             end)
    end
  end

  describe "edit/2" do
    test "returns the saved content after the editor exits" do
      assert Prompt.edit("hello\n", editor: "echo 'world' >> __FILE__") == "hello\nworld\n"
    end

    test "forwards :format so the temp file gets a matching extension" do
      result = Prompt.edit("hello\n", editor: "printf __FILE__ > __FILE__", format: "md")
      assert String.ends_with?(result, ".md")
    end
  end
end
