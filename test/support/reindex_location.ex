defmodule Algolia.TestSupport.ReindexLocation do
  use Ash.Resource,
    domain: Algolia.TestSupport.ReindexDomain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [Ash.Algolia]

  ets do
    private? true
  end

  algolia do
    index :locations do
      projection do
        load :translation_names

        compute :name, fn location ->
          [location.name | location.translation_names]
        end
      end
    end
  end

  actions do
    defaults [:read]

    create :create do
      accept [:name, :translations]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :translations, {:array, :string} do
      allow_nil? false
      default []
      public? true
    end
  end

  calculations do
    calculate :translation_names,
              {:array, :string},
              Algolia.TestSupport.ReindexLocation.TranslationNames
  end
end
