defmodule Mix.Releases.App do
  @moduledoc """
  Represents important metadata about a given application.
  """
  defstruct name: nil,
    vsn: nil,
    applications: [],
    included_applications: [],
    start_type: nil,
    path: nil

  @type start_type :: :permanent | :temporary | :transient | :load | :none
  @type t :: %__MODULE__{
    name: atom(),
    vsn: String.t,
    applications: [atom()],
    included_applications: [atom()],
    start_type: start_type,
    path: nil | String.t
  }

  @doc """
  Create a new Application struct from an application name
  """
  @spec new(atom) :: nil | __MODULE__.t | {:error, String.t}
  def new(name), do: new(name, nil)

  @doc """
  Same as new/1, but specify the application's start type
  """
  @spec new(atom, start_type | nil) :: nil | __MODULE__.t | {:error, String.t}
  def new(name, start_type)
    when is_atom(name) and start_type in [nil, :permanent, :temporary, :transient, :load, :none] do
    _ = Application.load(name)
    case Application.spec(name) do
      nil -> nil
      spec ->
        vsn      = '#{Keyword.get(spec, :vsn)}'
        deps     = get_children(name)
        apps     = Enum.uniq(deps ++ Keyword.get(spec, :applications, []))
        included = Keyword.get(spec, :included_applications, [])
        path     = Application.app_dir(name)
        %__MODULE__{name: name, vsn: vsn,
                    start_type: start_type,
                    applications: apps,
                    included_applications: included,
                    path: path}
    end
  end
  def new(name, start_type), do: {:error, "Invalid start type for #{name}: #{start_type}"}

  # Gets a list of all applications which are children
  # of this application.
  defp get_children(name) do
    try do
      Mix.Dep.loaded_by_name([name], [])
      |> Enum.flat_map(fn %Mix.Dep{deps: deps} -> deps end)
      |> Enum.filter_map(&include_dep?/1, &map_dep/1)
    rescue
      Mix.Error -> # This is a top-level app
        cond do
          Mix.Project.umbrella? ->
            # find the app in the umbrella
            app_path = Path.join(Mix.Project.config[:apps_path], "#{name}")
            cond do
              File.exists?(app_path) ->
                Mix.Project.in_project(name, app_path, fn mixfile ->
                  mixfile.project[:deps]
                  |> Enum.filter_map(&include_dep?/1, &map_dep/1)
                end)
              :else ->
                []
            end
          :else ->
            Mix.Project.config[:deps]
            |> Enum.filter_map(&include_dep?/1, &map_dep/1)
        end
    end
  end

  defp include_dep?({_, _}),               do: true
  defp include_dep?({_, _, opts}),         do: include_dep?(opts)
  defp include_dep?(%Mix.Dep{opts: opts}), do: include_dep?(opts)
  defp include_dep?(opts) when is_list(opts) do
    case Keyword.get(opts, :release) do
      false -> false
      true  ->
        case Keyword.get(opts, :only) do
          nil  -> true
          envs -> Enum.member?(envs, :prod)
        end
    end
  end

  defp map_dep({a, _}),           do: {a, :load}
  defp map_dep({a, _, _opts}),    do: {a, :load}
  defp map_dep(%Mix.Dep{app: a}), do: {a, :load}
end
