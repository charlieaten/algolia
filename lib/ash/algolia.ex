defmodule Ash.Algolia do
  @moduledoc """
  Spark DSL extension for configuring Algolia indexes on Ash resources.

  ## Example

      use Ash.Resource,
        extensions: [Ash.Algolia]

      algolia do
        index :venues do
          projection do
            load [:author, :tags]
            field :title
            field :body, &String.upcase/1
            compute :author_name, & &1.author.name
            compute :tag_names, fn resource -> Enum.map(resource.tags || [], & &1.name) end
          end

          settings do
            attributes_for_faceting [:location]
            hits_per_page 12
          end
        end
      end

  `Ash.Algolia.search/4`, `Ash.Algolia.reindex/2`, and
  `Ash.Algolia.reindex_atomic/2` use the configured index definitions at
  runtime.

  Ash resources using this extension do not need any Algolia functions injected
  into the resource module. `Ash.Algolia.Indexer` remains available as an
  explicit compatibility layer when `Algoliax.Indexer` behavior is still
  needed.
  """

  alias Ash.Algolia.{Index, Projection, Setting, Settings}
  alias Ash.Algolia.Projection.{ComputedField, Field, MappedField}
  alias Algoliax.Resources.Search, as: AlgoliaSearch

  @type index_name :: atom() | String.t()
  @type params :: map()
  @type search_opt :: {:index, index_name()} | {:search_module, module()}

  @algolia_setting_names Algoliax.Settings.settings()

  @setting_entities Enum.map(@algolia_setting_names, fn setting_name ->
                      %Spark.Dsl.Entity{
                        name: setting_name,
                        target: Setting,
                        describe: "Sets the Algolia `#{setting_name}` setting.",
                        args: [:value],
                        identifier: :name,
                        auto_set_fields: [name: setting_name],
                        schema: [
                          value: [
                            type: :any,
                            required: true,
                            doc: "The value forwarded to Algolia for `#{setting_name}`."
                          ]
                        ]
                      }
                    end)

  @settings %Spark.Dsl.Entity{
    name: :settings,
    target: Settings,
    describe: "Configures Algolia settings for this index.",
    entities: [entries: @setting_entities]
  }

  @map %Spark.Dsl.Entity{
    name: :map,
    target: MappedField,
    describe: "Projects one or more attributes from the record into the Algolia object.",
    args: [:fields],
    schema: [
      fields: [
        type: {:wrap_list, :atom},
        required: true,
        doc: "The record attributes to copy directly into the Algolia object."
      ]
    ]
  }

  @compute %Spark.Dsl.Entity{
    name: :compute,
    target: ComputedField,
    describe: "Computes an Algolia object field from the loaded record.",
    args: [:name, :computation],
    identifier: :name,
    schema: [
      name: [
        type: {:or, [:atom, :string]},
        required: true,
        doc: "The Algolia object field name."
      ],
      computation: [
        type: {:fun, 1},
        required: true,
        doc: "An arity-1 function that receives the record and returns the field value."
      ]
    ]
  }

  @field %Spark.Dsl.Entity{
    name: :field,
    target: Field,
    describe: "Projects a single Algolia object field from the selected field value.",
    args: [:name, {:optional, :transform}],
    identifier: :name,
    schema: [
      name: [
        type: {:or, [:atom, :string]},
        required: true,
        doc: "The Algolia object field name."
      ],
      transform: [
        type: {:fun, 1},
        doc: "An optional arity-1 function that receives the picked field value."
      ]
    ]
  }

  @projection %Spark.Dsl.Entity{
    name: :projection,
    target: Projection,
    describe: "Projects resource data into an Algolia object body.",
    schema: [
      object_id: [
        type: :atom,
        default: :id,
        doc: "The attribute used for Algolia object IDs. Defaults to `:id`."
      ],
      load: [
        type: :any,
        doc: "Additional Ash loads required before evaluating projection mappings or computes."
      ]
    ],
    entities: [fields: [@field], maps: [@map], computes: [@compute]]
  }

  @index %Spark.Dsl.Entity{
    name: :index,
    target: Index,
    describe: "Declares an Algolia index for this resource.",
    args: [:name],
    identifier: :name,
    schema: [
      name: [
        type: {:or, [:atom, :string]},
        required: true,
        doc: "The Algolia index name."
      ]
    ],
    entities: [settings: [@settings], projection: [@projection]],
    singleton_entity_keys: [:settings, :projection]
  }

  @algolia %Spark.Dsl.Section{
    name: :algolia,
    describe: "Configure Algolia indexes and index settings for this Ash resource.",
    entities: [@index]
  }

  use Spark.Dsl.Extension, sections: [@algolia]

  @spec configured?(module()) :: boolean()
  def configured?(resource) when is_atom(resource) do
    resource
    |> indexes()
    |> Enum.any?()
  rescue
    _ -> false
  end

  @doc "Returns the Algolia index declarations configured on the resource."
  @spec indexes(module()) :: [Index.t()]
  def indexes(resource) when is_atom(resource) do
    Spark.Dsl.Extension.get_entities(resource, [:algolia])
  end

  @doc "Returns the configured Algolia index names for the resource."
  @spec index_names(module()) :: [index_name()]
  def index_names(resource) do
    Enum.map(indexes(resource), & &1.name)
  end

  @doc "Returns the named Algolia index configuration, or `nil` if it is not declared."
  @spec index(module(), index_name()) :: Index.t() | nil
  def index(resource, name) do
    Enum.find(indexes(resource), &same_name?(&1.name, name))
  end

  @doc """
  Builds the Algolia object body for a record using the configured `projection`.

  Pass `index: :name` for multi-index resources. If no projection is
  configured, an empty map is returned.
  """
  @spec object(module(), map(), keyword()) :: map()
  def object(resource, record, opts \\ [])
      when is_atom(resource) and is_map(record) and is_list(opts) do
    resource
    |> object_index(Keyword.get(opts, :index))
    |> case do
      nil ->
        %{}

      %Index{} = index ->
        object_from_index(resource, index, record)
    end
  end

  @doc false
  @spec algolia_query(module()) :: module() | Ash.Query.t()
  def algolia_query(resource) when is_atom(resource) do
    if function_exported?(resource, :algolia_query, 0) do
      resource.algolia_query()
    else
      resource
    end
  end

  @doc false
  @spec algolia_load(module()) :: term()
  def algolia_load(resource) when is_atom(resource) do
    resource
    |> resource_algolia_load()
    |> merge_loads(projection_load(resource))
  end

  @doc false
  @spec to_be_indexed?(module(), map()) :: boolean()
  def to_be_indexed?(resource, record) when is_atom(resource) and is_map(record) do
    if function_exported?(resource, :to_be_indexed?, 1) do
      resource.to_be_indexed?(record)
    else
      true
    end
  end

  @doc false
  @spec object_id(module(), keyword(), map(), keyword()) :: term()
  def object_id(resource, settings, record, opts \\ [])
      when is_atom(resource) and is_list(settings) and is_map(record) and is_list(opts) do
    if function_exported?(resource, :get_object_id, 1) do
      case resource.get_object_id(record) do
        :default ->
          Map.fetch!(record, Algoliax.Utils.object_id_attribute(settings))

        value ->
          to_string(value)
      end
    else
      case projection_object_id(resource, Keyword.get(opts, :index)) do
        nil ->
          Map.fetch!(record, Algoliax.Utils.object_id_attribute(settings))

        field ->
          Map.fetch!(record, field)
      end
    end
  end

  @doc "Returns the named Algolia index configuration or raises if it is missing."
  @spec index!(module(), index_name()) :: Index.t()
  def index!(resource, name) do
    case index(resource, name) do
      %Index{} = index ->
        index

      nil ->
        raise ArgumentError,
              "expected #{inspect(resource)} to define algolia index #{inspect(name)}"
    end
  end

  @doc """
  Returns the settings for the resource's only Algolia index.

  Raises if the resource defines zero or multiple indexes.
  """
  @spec settings!(module()) :: keyword()
  def settings!(resource) do
    resource
    |> only_index!()
    |> settings_for_index()
  end

  @doc "Returns the settings for a specific Algolia index."
  @spec settings(module(), index_name()) :: keyword()
  def settings(resource, index_name) do
    resource
    |> index!(index_name)
    |> settings_for_index()
  end

  @doc """
  Returns the shared settings across all configured indexes.

  This is useful when bridging to `Algoliax.Indexer`, which expects one shared
  Algolia settings keyword list.
  """
  @spec shared_settings!(module()) :: keyword()
  def shared_settings!(resource) do
    resource
    |> indexes()
    |> case do
      [] ->
        raise ArgumentError, "expected #{inspect(resource)} to define at least one algolia index"

      [index] ->
        settings_for_index(index)

      indexes ->
        settings =
          indexes
          |> Enum.map(&settings_for_index/1)
          |> Enum.uniq_by(&normalize_term/1)

        case settings do
          [settings] ->
            settings

          _ ->
            raise ArgumentError,
                  "`Ash.Algolia.Indexer` requires all configured indexes on #{inspect(resource)} " <>
                    "to share the same settings"
        end
    end
  end

  @doc """
  Searches the configured Algolia index or indexes for a resource.

  Pass `index: :name` to target a single declared index. When omitted and the
  resource declares multiple indexes, each index is queried independently and
  the responses are combined in the same shape used by `Algoliax`.
  """
  @spec search(module(), String.t(), params(), [search_opt()]) ::
          {:ok, Algoliax.Response.t() | [Algoliax.Responses.t()]} | {:error, term()}
  def search(resource, query, params \\ %{}, opts \\ [])
      when is_atom(resource) and is_binary(query) and is_map(params) and is_list(opts) do
    search_module = Keyword.get(opts, :search_module, AlgoliaSearch)

    case search_indexes(resource, Keyword.get(opts, :index)) do
      [index] ->
        search_module.search(resource, search_settings(index), query, params)

      indexes ->
        indexes
        |> Enum.map(&search_module.search(resource, search_settings(&1), query, params))
        |> Algoliax.Utils.render_response()
    end
  end

  @doc """
  Reindexes a resource through the Ash-native Algolia reindexer.
  """
  def reindex(resource) when is_atom(resource) do
    Ash.Algolia.Reindexer.reindex(resource, bridge_settings(resource), nil, [])
  end

  def reindex(resource, opts) when is_atom(resource) and is_list(opts) do
    Ash.Algolia.Reindexer.reindex(resource, bridge_settings(resource), nil, opts)
  end

  def reindex(resource, %Ash.Query{} = query) when is_atom(resource) do
    Ash.Algolia.Reindexer.reindex(resource, bridge_settings(resource), query, [])
  end

  def reindex(resource, %Ash.Query{} = query, opts) when is_atom(resource) and is_list(opts) do
    Ash.Algolia.Reindexer.reindex(resource, bridge_settings(resource), query, opts)
  end

  @doc """
  Atomically reindexes a resource through the Ash-native Algolia reindexer.
  """
  def reindex_atomic(resource) when is_atom(resource) do
    Ash.Algolia.Reindexer.reindex_atomic(resource, bridge_settings(resource), [])
  end

  def reindex_atomic(resource, opts) when is_atom(resource) and is_list(opts) do
    Ash.Algolia.Reindexer.reindex_atomic(resource, bridge_settings(resource), opts)
  end

  defp search_indexes(resource, nil) do
    case indexes(resource) do
      [] ->
        raise ArgumentError, "expected #{inspect(resource)} to define at least one algolia index"

      indexes ->
        indexes
    end
  end

  defp search_indexes(resource, index_name), do: [index!(resource, index_name)]

  defp search_settings(%Index{} = index) do
    [index_name: [index.name], algolia: settings_for_index(index)]
  end

  defp bridge_settings(resource) do
    [index_name: index_names(resource), algolia: shared_settings!(resource)]
  end

  defp object_index(resource, nil) do
    case indexes(resource) do
      [%Index{} = index] -> index
      _ -> nil
    end
  end

  defp object_index(resource, index_name) do
    case index(resource, index_name) do
      %Index{} = index ->
        index

      nil ->
        raise ArgumentError,
              "expected #{inspect(resource)} to define algolia index #{inspect(index_name)}"
    end
  end

  defp object_from_index(resource, %Index{projection: %Projection{} = projection}, record) do
    Projection.project(projection, resource, record)
  end

  defp object_from_index(_resource, %Index{}, _record), do: %{}

  defp projection_load(resource) when is_atom(resource) do
    resource
    |> indexes()
    |> Enum.map(&projection_load/1)
    |> Enum.reject(&(&1 in [nil, []]))
    |> Enum.reduce(nil, &merge_loads/2)
  end

  defp projection_load(%Index{projection: %Projection{load: load}}), do: load
  defp projection_load(%Index{}), do: nil

  defp projection_object_id(resource, nil) do
    resource
    |> indexes()
    |> Enum.map(&projection_object_id/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> case do
      [] ->
        nil

      [field] ->
        field

      fields ->
        raise ArgumentError,
              "expected #{inspect(resource)} to use one projection `object_id` value across indexes, " <>
                "got #{inspect(fields)}"
    end
  end

  defp projection_object_id(resource, index_name) do
    resource
    |> index(index_name)
    |> case do
      %Index{} = index ->
        projection_object_id(index)

      nil ->
        raise ArgumentError,
              "expected #{inspect(resource)} to define algolia index #{inspect(index_name)}"
    end
  end

  defp projection_object_id(%Index{projection: %Projection{object_id: object_id}}), do: object_id
  defp projection_object_id(%Index{}), do: nil

  defp resource_algolia_load(resource) do
    if function_exported?(resource, :algolia_load, 0) do
      resource.algolia_load()
    else
      nil
    end
  end

  defp merge_loads(nil, nil), do: []
  defp merge_loads(nil, right), do: right
  defp merge_loads(left, nil), do: left

  defp merge_loads(left, right) do
    Enum.uniq(List.wrap(left) ++ List.wrap(right))
  end

  defp settings_for_index(%Index{settings: nil}), do: []

  defp settings_for_index(%Index{settings: %Settings{entries: entries}}) do
    Enum.map(entries, &{&1.name, &1.value})
  end

  defp only_index!(resource) do
    case indexes(resource) do
      [index] ->
        index

      [] ->
        raise ArgumentError, "expected #{inspect(resource)} to define at least one algolia index"

      indexes ->
        raise ArgumentError,
              "expected #{inspect(resource)} to define exactly one algolia index, got #{length(indexes)}"
    end
  end

  defp same_name?(left, right), do: to_string(left) == to_string(right)

  defp normalize_term(value) when is_list(value) do
    if Keyword.keyword?(value) do
      value
      |> Enum.map(fn {key, item} -> {key, normalize_term(item)} end)
      |> Enum.sort_by(fn {key, _value} -> to_string(key) end)
    else
      Enum.map(value, &normalize_term/1)
    end
  end

  defp normalize_term(value) when is_map(value) do
    value
    |> Enum.map(fn {key, item} -> {key, normalize_term(item)} end)
    |> Enum.sort_by(fn {key, _value} -> inspect(key) end)
  end

  defp normalize_term(value), do: value
end
