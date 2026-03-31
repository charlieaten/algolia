defmodule Ash.Algolia.Projection.Field do
  @moduledoc false

  @type t :: %__MODULE__{
          __identifier__: atom() | String.t() | nil,
          name: atom() | String.t() | nil,
          transform: (term() -> term()) | nil,
          __spark_metadata__: Spark.Dsl.Entity.spark_meta() | nil
        }

  defstruct __identifier__: nil,
            name: nil,
            transform: nil,
            __spark_metadata__: nil
end
