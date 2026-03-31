defmodule Ash.Algolia.Projection.MappedField do
  @moduledoc false

  @type t :: %__MODULE__{
          fields: [atom()],
          __spark_metadata__: Spark.Dsl.Entity.spark_meta() | nil
        }

  defstruct fields: [], __spark_metadata__: nil
end
