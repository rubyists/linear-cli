defmodule LinearCli.CLI.Commands.Profiles do
  @moduledoc """
  Profile commands: create, list, use, show, clear, and delete.
  New in this port - Ruby has no equivalent.
  """

  alias LinearCli.CLI.{Display, Output, Prompt}
  alias LinearCli.Profiles

  @doc """
  New in this port - Ruby has no equivalent. Saves a new named
  team/project bundle (`LinearCli.Profiles.create/2`) that `profile use`
  can later switch to.
  """
  def profile_create(%{args: %{name: name}, options: options}) do
    case Profiles.create(name, team: options.team, project: options.project) do
      {:ok, profile} ->
        Display.show(profile, %{output: options.output})
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "New in this port - Ruby has no equivalent. Lists every saved profile."
  def profile_list(%{options: options}) do
    Display.show(Profiles.list(), %{output: options.output})
    :ok
  end

  @doc """
  New in this port - Ruby has no equivalent. Switches the active profile -
  its team/project become the defaults `issue create`/`issue list` fall
  back to when `--team`/`--project` are omitted.
  """
  def profile_use(%{args: %{name: name}, options: options}) do
    case Profiles.activate(name) do
      :ok ->
        if Output.json?(options) do
          Output.success("profile_use", %{"profile" => name}, options)
        else
          Prompt.ok("Switched to profile #{name}")
        end

        :ok

      {:error, :not_found} ->
        {:error, {:smells_bad, "No profile named #{name}"}}
    end
  end

  @doc "New in this port - Ruby has no equivalent. Shows the active profile, if any."
  def profile_show(%{options: options}) do
    case Profiles.active() do
      nil ->
        if Output.json?(options) do
          Output.status(:warn, "No active profile", options)
          Display.show(nil, %{output: "json"})
        else
          Prompt.warn("No active profile")
        end

      profile ->
        Display.show(profile, %{output: options.output})
    end

    :ok
  end

  @doc "New in this port - Ruby has no equivalent. Deactivates the active profile without deleting it."
  def profile_clear(%{options: options}) do
    Profiles.clear()

    if Output.json?(options) do
      Output.success("profile_clear", %{}, options)
    else
      Prompt.ok("Cleared active profile")
    end

    :ok
  end

  @doc "New in this port - Ruby has no equivalent. Deletes a saved profile."
  def profile_delete(%{args: %{name: name}, options: options}) do
    case Profiles.delete(name) do
      :ok ->
        if Output.json?(options) do
          Output.success("profile_delete", %{"profile" => name}, options)
        else
          Prompt.ok("Deleted profile #{name}")
        end

        :ok

      {:error, :not_found} ->
        {:error, {:smells_bad, "No profile named #{name}"}}
    end
  end
end
