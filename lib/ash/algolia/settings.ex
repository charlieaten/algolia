defmodule Ash.Algolia.Settings do
  @moduledoc false

  alias Ash.Algolia.Setting

  @type t :: %__MODULE__{
          entries: [Setting.t()],
          __spark_metadata__: Spark.Dsl.Entity.spark_meta() | nil
        }

  defstruct entries: [], __spark_metadata__: nil
end
