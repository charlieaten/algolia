defmodule Ash.Algolia.Indexer do
  @moduledoc """
  Optional compatibility macro that bridges `Ash.Algolia` resource
  configuration into `Algoliax.Indexer` APIs.

  `index_name` and `algolia` are derived from the Ash DSL, so they should not
  be passed directly to this macro. Reindexing uses Ash queries and streaming,
  so `:repo` is not needed either.

  Ash resources using `extensions: [Ash.Algolia]` do not need this macro unless
  they explicitly want the `Algoliax.Indexer`-style function surface.

  Resources can override:

  - `algolia_query/0` to provide a base `Ash.Query`
  - `algolia_load/0` to declare fields/relationships required beyond the configured projection loads
  """

  defmacro __using__(opts) do
    if Keyword.has_key?(opts, :algolia) do
      raise ArgumentError, "`Ash.Algolia.Indexer` derives `:algolia` from the `algolia` DSL block"
    end

    if Keyword.has_key?(opts, :index_name) do
      raise ArgumentError,
            "`Ash.Algolia.Indexer` derives `:index_name` from the `algolia` DSL block"
    end

    if Keyword.has_key?(opts, :repo) do
      raise ArgumentError,
            "`Ash.Algolia.Indexer` reindexes via Ash semantics, so `:repo` is no longer needed"
    end

    quote bind_quoted: [
            settings:
              Keyword.merge(
                opts,
                index_name: :__ash_algolia_index_names__,
                algolia: :__ash_algolia_settings__
              )
          ] do
      @behaviour Algoliax.Indexer
      @settings settings

      alias Algoliax.Resources.{Index, Object, Search}

      @impl Algoliax.Indexer
      def search(query, params \\ %{}) do
        Search.search(__MODULE__, @settings, query, params)
      end

      @impl Algoliax.Indexer
      def search_facet(facet_name, facet_query \\ nil, params \\ %{}) do
        Search.search_facet(__MODULE__, @settings, facet_name, facet_query, params)
      end

      @impl Algoliax.Indexer
      def get_settings do
        Index.get_settings(__MODULE__, @settings)
      end

      @impl Algoliax.Indexer
      def configure_index do
        Index.configure_index(__MODULE__, @settings)
      end

      @impl Algoliax.Indexer
      def delete_index do
        Index.delete_index(__MODULE__, @settings)
      end

      @impl Algoliax.Indexer
      def save_objects(models, opts \\ []) do
        Object.save_objects(__MODULE__, @settings, models, opts)
      end

      @impl Algoliax.Indexer
      def save_object(model) do
        Object.save_object(__MODULE__, @settings, model)
      end

      @impl Algoliax.Indexer
      def delete_object(model) do
        Object.delete_object(__MODULE__, @settings, model)
      end

      @impl Algoliax.Indexer
      def delete_by(matching_filter) do
        Object.delete_by(__MODULE__, @settings, matching_filter)
      end

      @impl Algoliax.Indexer
      def get_object(model) do
        Object.get_object(__MODULE__, @settings, model)
      end

      def reindex do
        Ash.Algolia.Reindexer.reindex(__MODULE__, @settings, nil, [])
      end

      @impl Algoliax.Indexer
      def reindex(opts) when is_list(opts) do
        Ash.Algolia.Reindexer.reindex(__MODULE__, @settings, nil, opts)
      end

      def reindex(%Ash.Query{} = query) do
        Ash.Algolia.Reindexer.reindex(__MODULE__, @settings, query, [])
      end

      def reindex(resource) when is_atom(resource) do
        Ash.Algolia.Reindexer.reindex(__MODULE__, @settings, resource, [])
      end

      @impl Algoliax.Indexer
      def reindex(%Ash.Query{} = query, opts) when is_list(opts) do
        Ash.Algolia.Reindexer.reindex(__MODULE__, @settings, query, opts)
      end

      def reindex(resource, opts) when is_atom(resource) and is_list(opts) do
        Ash.Algolia.Reindexer.reindex(__MODULE__, @settings, resource, opts)
      end

      @impl Algoliax.Indexer
      def reindex_atomic do
        Ash.Algolia.Reindexer.reindex_atomic(__MODULE__, @settings, [])
      end

      def reindex_atomic(opts) when is_list(opts) do
        Ash.Algolia.Reindexer.reindex_atomic(__MODULE__, @settings, opts)
      end

      def __ash_algolia_index_names__, do: Ash.Algolia.index_names(__MODULE__)
      def __ash_algolia_settings__, do: Ash.Algolia.shared_settings!(__MODULE__)

      def algolia_query, do: __MODULE__
      def algolia_load, do: []

      @impl Algoliax.Indexer
      def build_object(record) do
        Ash.Algolia.object(__MODULE__, record)
      end

      @impl Algoliax.Indexer
      def build_object(record, index_name) do
        Ash.Algolia.object(__MODULE__, record, index: index_name)
      end

      @impl Algoliax.Indexer
      def to_be_indexed?(_) do
        true
      end

      @impl Algoliax.Indexer
      def get_object_id(record) do
        Ash.Algolia.object_id(__MODULE__, @settings, record)
      end

      defoverridable(
        algolia_query: 0,
        algolia_load: 0,
        to_be_indexed?: 1,
        build_object: 1,
        build_object: 2,
        get_object_id: 1
      )
    end
  end
end
