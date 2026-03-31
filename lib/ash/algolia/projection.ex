defmodule Ash.Algolia.Projection do
  @moduledoc false

  alias Ash.Algolia.Projection.{ComputedField, Field, MappedField}

  @type t :: %__MODULE__{
          object_id: atom(),
          load: term(),
          fields: [Field.t()],
          maps: [MappedField.t()],
          computes: [ComputedField.t()],
          __spark_metadata__: Spark.Dsl.Entity.spark_meta() | nil
        }

  defstruct object_id: :id,
            load: nil,
            fields: [],
            maps: [],
            computes: [],
            __spark_metadata__: nil

  @spec project(t(), module(), map()) :: map()
  def project(%__MODULE__{} = projection, _resource, record) when is_map(record) do
    projection.maps
    |> Enum.reduce(%{}, fn %MappedField{fields: fields}, acc ->
      Enum.reduce(fields, acc, fn field, mapped ->
        Map.put(mapped, field, Map.fetch!(record, field))
      end)
    end)
    |> then(fn mapped ->
      Enum.reduce(projection.computes, mapped, fn %ComputedField{
                                                    name: name,
                                                    computation: computation
                                                  },
                                                  computed ->
        Map.put(computed, name, computation.(record))
      end)
    end)
    |> then(fn projected ->
      Enum.reduce(projection.fields, projected, fn %Field{name: name, transform: transform},
                                                   acc ->
        Map.put(acc, name, project_field(record, name, transform))
      end)
    end)
  end

  defp project_field(record, name, nil) do
    Map.fetch!(record, name)
  end

  defp project_field(record, name, transform) do
    record
    |> Map.fetch!(name)
    |> transform.()
  end
end
