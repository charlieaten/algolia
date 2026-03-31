defmodule Ash.AlgoliaTest do
  use ExUnit.Case, async: true

  alias Algoliax.Response
  alias Algoliax.Responses
  alias Algolia.TestSupport.AshAlgoliaResources.{MultiIndexVenue, ProjectedArticle, Venue}

  defmodule SearchStub do
    def search(_resource, settings, query, params) do
      [index_name: [index_name], algolia: algolia_settings] = settings

      Response.new(
        %{
          "hits" => [%{"objectID" => to_string(index_name)}],
          "query" => query,
          "settings" =>
            Enum.into(algolia_settings, %{}, fn {key, value} -> {to_string(key), value} end),
          "params" => params
        },
        index_name: index_name
      )
    end
  end

  test "exposes configured indexes and canonical settings" do
    assert Ash.Algolia.index_names(Venue) == [:venues]

    assert Ash.Algolia.settings!(Venue) == [
             attributes_for_faceting: [:location],
             hits_per_page: 12
           ]
  end

  test "search delegates to the configured index" do
    assert {:ok, %Response{} = response} =
             Ash.Algolia.search(Venue, "pizza", %{page: 1}, search_module: SearchStub)

    assert response.params[:index_name] == :venues
    assert response.response["query"] == "pizza"
    assert response.response["settings"]["attributes_for_faceting"] == [:location]
  end

  test "object builds from the configured projection" do
    venue = struct(Venue, location: "Nairobi")
    rated_venue = struct(MultiIndexVenue, rating: 5)

    assert Ash.Algolia.object(Venue, venue) == %{location: "Nairobi"}
    assert Ash.Algolia.object(Venue, venue, index: :venues) == %{location: "Nairobi"}

    assert Ash.Algolia.object(MultiIndexVenue, rated_venue, index: :venues) == %{
             scope: :default,
             rating: 5
           }

    assert Ash.Algolia.object(MultiIndexVenue, rated_venue, index: :venues_by_rating) == %{
             scope: :rating,
             rating: 5
           }
  end

  test "projection uses field values for fields and full records for computes" do
    published_at = ~U[2026-01-01 00:00:00Z]

    article = %{
      id: "article-id",
      slug: "ash-algolia",
      title: "Ash Algolia",
      body: "Projection DSL",
      published_at: published_at,
      author: %{name: "Charlie"},
      tags: [%{name: "ash"}, %{name: "algolia"}]
    }

    assert Ash.Algolia.object(ProjectedArticle, article) == %{
             title: "Ash Algolia",
             body: "PROJECTION DSL",
             published_at: published_at,
             author_name: "Charlie",
             tag_names: ["ash", "algolia"]
           }

    assert Enum.sort(Ash.Algolia.algolia_load(ProjectedArticle)) == [:author, :tags]
    assert Ash.Algolia.object_id(ProjectedArticle, [], article) == "ash-algolia"
    assert Ash.Algolia.object_id(Venue, [], %{id: "venue-id"}) == "venue-id"
  end

  test "resources do not get Algoliax-style functions injected" do
    refute function_exported?(Venue, :search, 1)
    refute function_exported?(Venue, :reindex, 0)
    refute function_exported?(Venue, :build_object, 1)
  end

  test "search can query all configured indexes" do
    assert {:ok, responses} =
             Ash.Algolia.search(MultiIndexVenue, "pizza", %{}, search_module: SearchStub)

    assert Enum.all?(responses, &match?(%Responses{}, &1))

    assert responses
           |> Enum.map(& &1.index_name)
           |> Enum.sort() == [:venues, :venues_by_rating]
  end

  test "shared_settings! raises when indexes diverge" do
    assert_raise ArgumentError, ~r/requires all configured indexes/, fn ->
      Ash.Algolia.shared_settings!(MultiIndexVenue)
    end
  end
end
