defmodule Algolia.TestSupport.ReindexLocation.TranslationNames do
  use Ash.Resource.Calculation

  @impl Ash.Resource.Calculation
  def calculate(records, _opts, _context) do
    Enum.map(records, &(&1.translations || []))
  end
end
