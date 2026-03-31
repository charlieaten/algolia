defmodule Ash.Algolia.Setting do
  @moduledoc false

  @type t :: %__MODULE__{
          __identifier__: atom() | nil,
          name: atom(),
          value: term(),
          __spark_metadata__: Spark.Dsl.Entity.spark_meta() | nil
        }

  defstruct __identifier__: nil, name: nil, value: nil, __spark_metadata__: nil
end
