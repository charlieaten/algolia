defmodule Ash.Algolia.Object do
  @moduledoc false

  import Algoliax.Client, only: [request: 1]
  import Algoliax.Utils, only: [index_name: 2, render_response: 1]

  def save_objects(resource, settings, models, opts) do
    resource
    |> index_name(settings)
    |> Enum.map(fn index_name ->
      requests = build_requests(resource, settings, models, index_name, opts)

      if requests != [] do
        request(%{
          action: :save_objects,
          url_params: [index_name: index_name],
          body: %{requests: requests}
        })
      end
    end)
    |> render_response()
  end

  defp build_requests(resource, settings, models, index_name, opts) do
    models
    |> Enum.map(&build_request(resource, settings, &1, index_name, opts))
    |> Enum.reject(&is_nil/1)
  end

  defp build_request(resource, settings, model, index_name, opts) do
    case action(resource, model, opts) do
      nil ->
        nil

      "deleteObject" = action ->
        %{
          action: action,
          body: %{objectID: Ash.Algolia.object_id(resource, settings, model, index: index_name)}
        }

      action ->
        %{
          action: action,
          body:
            resource
            |> Ash.Algolia.object(model, index: index_name)
            |> Map.put(
              :objectID,
              Ash.Algolia.object_id(resource, settings, model, index: index_name)
            )
        }
    end
  end

  defp action(resource, model, opts) do
    if Ash.Algolia.to_be_indexed?(resource, model) do
      "updateObject"
    else
      if Keyword.get(opts, :force_delete) do
        "deleteObject"
      end
    end
  end
end
