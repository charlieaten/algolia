defmodule Ash.Algolia.Index do
  @moduledoc false

  alias Ash.Algolia.{Projection, Settings}

  @type t :: %__MODULE__{
          __identifier__: atom() | String.t() | nil,
          name: atom() | String.t(),
          projection: Projection.t() | nil,
          settings: Settings.t() | nil,
          __spark_metadata__: Spark.Dsl.Entity.spark_meta() | nil
        }

  defstruct __identifier__: nil,
            name: nil,
            projection: nil,
            settings: nil,
            __spark_metadata__: nil
end
