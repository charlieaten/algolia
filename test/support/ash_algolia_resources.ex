defmodule Algolia.TestSupport.AshAlgoliaResources.Venue do
  use Ash.Resource, data_layer: :embedded, extensions: [Ash.Algolia]

  algolia do
    index :venues do
      projection do
        field :location
      end

      settings do
        attributes_for_faceting [:location]
        hits_per_page 12
      end
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :location, :string
  end
end

defmodule Algolia.TestSupport.AshAlgoliaResources.MultiIndexVenue do
  use Ash.Resource, data_layer: :embedded, extensions: [Ash.Algolia]

  algolia do
    index :venues do
      projection do
        field :rating
        compute :scope, fn _venue -> :default end
      end

      settings do
        hits_per_page 12
      end
    end

    index :venues_by_rating do
      projection do
        field :rating
        compute :scope, fn _venue -> :rating end
      end

      settings do
        custom_ranking ["desc(rating)"]
      end
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :rating, :integer
  end
end

defmodule Algolia.TestSupport.AshAlgoliaResources.ProjectedArticle do
  use Ash.Resource, data_layer: :embedded, extensions: [Ash.Algolia]

  algolia do
    index :articles do
      projection do
        object_id :slug
        load [:author, :tags]
        field :title
        field :body, &String.upcase/1
        field :published_at
        compute :author_name, & &1.author.name

        compute :tag_names, fn resource ->
          Enum.map(resource.tags || [], & &1.name)
        end
      end
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :slug, :string
    attribute :title, :string
    attribute :body, :string
    attribute :published_at, :utc_datetime
    attribute :author, :map
    attribute :tags, {:array, :map}
  end
end
