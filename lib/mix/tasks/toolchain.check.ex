defmodule Mix.Tasks.Toolchain.Check do
  @shortdoc "Checks that CI and mise use the same OTP and Elixir versions"

  @moduledoc """
  #{@shortdoc}.

      mix toolchain.check

  `mise.toml` is the local toolchain source of truth. This task rejects a
  workflow that configures erlef/setup-beam with different OTP or Elixir pins.
  """

  use Mix.Task

  @impl Mix.Task
  def run([]) do
    workflows =
      ".github/workflows/*.yaml"
      |> Path.wildcard()
      |> Enum.map(&{&1, File.read!(&1)})

    case validate(File.read!("mise.toml"), workflows) do
      :ok -> :ok
      {:error, message} -> Mix.raise(message)
    end
  end

  def run(_argv), do: Mix.raise("Usage: mix toolchain.check")

  @doc false
  def validate(mise_toml, workflows) do
    expected = %{otp: pin!(mise_toml, "erlang"), elixir: pin!(mise_toml, "elixir")}

    mismatches =
      Enum.flat_map(workflows, fn {path, workflow} ->
        Enum.flat_map(setup_beam_steps(workflow), fn step ->
          Enum.flat_map(expected, fn {name, expected_pin} ->
            case Map.get(workflow_pins(step), name) do
              ^expected_pin -> []
              nil -> ["#{path}: #{name} missing (expected #{expected_pin})"]
              pin -> ["#{path}: #{name} #{pin} (expected #{expected_pin})"]
            end
          end)
        end)
      end)

    case mismatches do
      [] -> :ok
      _ -> {:error, "Toolchain pins differ from mise.toml:\n  #{Enum.join(mismatches, "\n  ")}"}
    end
  end

  defp pin!(contents, name) do
    case Regex.run(~r/^#{name}\s*=\s*"([^"]+)"$/m, contents) do
      [_, pin] -> pin
      nil -> Mix.raise("mise.toml does not pin #{name}")
    end
  end

  defp workflow_pins(workflow) do
    Regex.scan(~r/^\s*(otp|elixir)-version:\s*"([^"]+)"$/m, workflow)
    |> Map.new(fn [_, name, pin] -> {if(name == "otp", do: :otp, else: :elixir), pin} end)
  end

  defp setup_beam_steps(workflow) do
    workflow
    |> String.split(~r/\n(?=\s*-\s*$)/m)
    |> Enum.filter(&String.contains?(&1, "uses: erlef/setup-beam@v1"))
  end
end
