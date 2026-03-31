defmodule Ash.Algolia.Reindexer do
  @moduledoc false

  import Algoliax.Client, only: [request: 1]

  alias Algoliax.Resources.Index
  alias Algoliax.SettingsStore

  @batch_size Application.compile_env(:algoliax, :batch_size, 500)

  def reindex(module, settings, query_or_resource, opts) when is_list(opts) do
    object_module = Keyword.get(opts, :object_module, Ash.Algolia.Object)
    save_options = save_options(opts)
    stream_options = stream_options(opts)

    query_or_resource
    |> query(module, opts)
    |> Ash.stream!(stream_options)
    |> Stream.chunk_every(stream_options[:batch_size])
    |> Enum.map(&object_module.save_objects(module, settings, &1, save_options))
    |> render_reindex()
  end

  def reindex_atomic(module, settings, opts) when is_list(opts) do
    query = Keyword.get(opts, :query)
    reindex_opts = Keyword.delete(opts, :query)

    module
    |> Algoliax.Utils.index_name(settings)
    |> Enum.map(fn index_name ->
      tmp_index_name = :"#{index_name}.tmp"

      tmp_settings =
        settings |> Keyword.put(:index_name, tmp_index_name) |> Keyword.delete(:replicas)

      SettingsStore.start_reindexing(index_name)

      try do
        reindex(module, tmp_settings, query, reindex_opts)

        request(%{
          action: :move_index,
          url_params: [index_name: tmp_index_name],
          body: %{operation: "move", destination: "#{index_name}"}
        })

        {:ok, :completed}
      after
        Index.delete_index(module, tmp_settings)
        SettingsStore.delete_settings(tmp_index_name)
        SettingsStore.stop_reindexing(index_name)
      end
    end)
    |> render_reindex_atomic()
  end

  defp query(nil, module, opts) do
    module
    |> Ash.Algolia.algolia_query()
    |> Ash.Query.new()
    |> maybe_load(module, Keyword.get(opts, :load))
  end

  defp query(%Ash.Query{} = query, module, opts) do
    maybe_load(query, module, Keyword.get(opts, :load))
  end

  defp query(resource, module, opts) when is_atom(resource) do
    resource
    |> Ash.Query.new()
    |> maybe_load(module, Keyword.get(opts, :load))
  end

  defp maybe_load(query, module, additional_load) do
    [Ash.Algolia.algolia_load(module), additional_load]
    |> Enum.reject(&(&1 in [nil, []]))
    |> Enum.reduce(query, &Ash.Query.load(&2, &1))
  end

  defp stream_options(opts) do
    opts
    |> Keyword.get(:stream_options, [])
    |> Keyword.put_new(:batch_size, @batch_size)
  end

  defp save_options(opts) do
    opts
    |> Keyword.get(:save_options, [])
    |> maybe_put(:force_delete, opts[:force_delete])
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp render_reindex(responses) do
    results =
      responses
      |> Enum.reject(&is_nil/1)
      |> case do
        [] ->
          []

        [{:ok, %Algoliax.Response{}} | _] = single_index_responses ->
          single_index_responses

        [{:ok, [%Algoliax.Responses{} | _]} | _] = multiple_index_responses ->
          multiple_index_responses
          |> Enum.reduce([], fn {:ok, responses}, acc -> acc ++ responses end)
          |> Enum.group_by(& &1.index_name)
          |> Enum.map(fn {index_name, list} ->
            %Algoliax.Responses{
              index_name: index_name,
              responses: Enum.flat_map(list, & &1.responses)
            }
          end)
      end

    {:ok, results}
  end

  defp render_reindex_atomic([response]), do: response
  defp render_reindex_atomic([_ | _] = responses), do: responses
end
