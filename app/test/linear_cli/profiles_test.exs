defmodule LinearCli.ProfilesTest do
  # Not async: every test in this module shares the one sqlite file at
  # `config :linear_cli, :profiles_db_path` (config/runtime.exs) - `setup`
  # below deletes it fresh before each test instead.
  use ExUnit.Case, async: false

  alias LinearCli.Profiles
  alias LinearCli.Profiles.Profile

  setup do
    path = Application.fetch_env!(:linear_cli, :profiles_db_path)
    File.rm(path)
    :ok
  end

  describe "create/2 and list/0" do
    test "saves a profile with the given team/project and lists it back" do
      assert {:ok, %Profile{name: "manhattan", team: "CRY", project: "Manhattan"}} =
               Profiles.create("manhattan", team: "CRY", project: "Manhattan")

      assert [%Profile{name: "manhattan", team: "CRY", project: "Manhattan", active: false}] =
               Profiles.list()
    end

    test "team/project are optional" do
      assert {:ok, %Profile{team: nil, project: nil}} = Profiles.create("bare")
    end

    test "lists multiple profiles ordered by name" do
      {:ok, _} = Profiles.create("zeta")
      {:ok, _} = Profiles.create("alpha")

      assert [%Profile{name: "alpha"}, %Profile{name: "zeta"}] = Profiles.list()
    end

    test "rejects a duplicate name" do
      {:ok, _} = Profiles.create("dup")
      assert {:error, _reason} = Profiles.create("dup")
    end
  end

  describe "activate/1 and active/0" do
    test "with no active profile, active/0 returns nil" do
      assert Profiles.active() == nil
    end

    test "activating a profile makes it the active one" do
      {:ok, _} = Profiles.create("manhattan", team: "CRY", project: "Manhattan")

      assert :ok = Profiles.activate("manhattan")
      assert %Profile{name: "manhattan", active: true} = Profiles.active()
    end

    test "activating a second profile deactivates the first" do
      {:ok, _} = Profiles.create("manhattan", team: "CRY")
      {:ok, _} = Profiles.create("platform", team: "ENG")

      :ok = Profiles.activate("manhattan")
      :ok = Profiles.activate("platform")

      assert %Profile{name: "platform", active: true} = Profiles.active()
      assert [manhattan, platform] = Profiles.list()
      refute manhattan.active
      assert platform.active
    end

    test "activating an unknown profile returns :not_found" do
      assert {:error, :not_found} = Profiles.activate("nope")
    end
  end

  describe "delete/1" do
    test "removes the profile" do
      {:ok, _} = Profiles.create("manhattan")
      assert :ok = Profiles.delete("manhattan")
      assert Profiles.list() == []
    end

    test "deleting an unknown profile returns :not_found" do
      assert {:error, :not_found} = Profiles.delete("nope")
    end
  end

  describe "default_team/0 and default_project/0" do
    test "nil with no active profile" do
      assert Profiles.default_team() == nil
      assert Profiles.default_project() == nil
    end

    test "the active profile's team/project once one is activated" do
      {:ok, _} = Profiles.create("manhattan", team: "CRY", project: "Manhattan")
      :ok = Profiles.activate("manhattan")

      assert Profiles.default_team() == "CRY"
      assert Profiles.default_project() == "Manhattan"
    end
  end
end
