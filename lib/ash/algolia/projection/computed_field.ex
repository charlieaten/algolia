defmodule Ash.Algolia.Projection.ComputedField do
  @moduledoc false

  @type t :: %__MODULE__{
          __identifier__: atom() | String.t() | nil,
          name: atom() | String.t() | nil,
          computation: (map() -> term()) | nil,
          __spark_metadata__: Spark.Dsl.Entity.spark_meta() | nil
        }

  defstruct __identifier__: nil, name: nil, computation: nil, __spark_metadata__: nil
end
