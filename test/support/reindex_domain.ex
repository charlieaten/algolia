defmodule Algolia.TestSupport.ReindexDomain do
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource Algolia.TestSupport.ReindexLocation
  end
end
