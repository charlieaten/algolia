defmodule Ash.AlgoliaReindexTest do
  use ExUnit.Case, async: false

  require Ash.Query

  alias Algolia.TestSupport.ReindexLocation

  defmodule ObjectStub do
    def save_objects(module, settings, batch, opts) do
      send(opts[:test_pid], {:saved_batch, module, settings, batch})

      Algoliax.Response.new(
        %{"taskID" => 1, "updatedAt" => "2026-01-01T00:00:00Z"},
        index_name: settings[:index_name] |> List.wrap() |> List.first()
      )
    end
  end

  setup do
    Ash.DataLayer.Ets.stop(ReindexLocation)
    :ok
  end

  test "Ash.Algolia.reindex/2 streams Ash resources without a repo and applies projection loads" do
    ReindexLocation
    |> Ash.Changeset.for_create(:create, %{
      name: "Nairobi",
      translations: ["나이로비"]
    })
    |> Ash.create!()

    assert {:ok, [_response]} =
             Ash.Algolia.reindex(
               ReindexLocation,
               object_module: ObjectStub,
               save_options: [test_pid: self()],
               stream_options: [batch_size: 1]
             )

    assert_receive {:saved_batch, Algolia.TestSupport.ReindexLocation, _settings, [location]}
    assert location.translation_names == ["나이로비"]
  end

  test "resources do not get reindex injected" do
    refute function_exported?(ReindexLocation, :reindex, 0)
    refute function_exported?(ReindexLocation, :reindex, 1)
  end

  test "Ash.Algolia.reindex/2 supports an explicit Ash query" do
    ReindexLocation
    |> Ash.Changeset.for_create(:create, %{
      name: "Seoul",
      translations: ["서울"]
    })
    |> Ash.create!()

    query = Ash.Query.filter(ReindexLocation, name == "Seoul")

    assert {:ok, [_response]} =
             Ash.Algolia.reindex(
               ReindexLocation,
               query,
               object_module: ObjectStub,
               save_options: [test_pid: self()],
               stream_options: [batch_size: 1]
             )

    assert_receive {:saved_batch, Algolia.TestSupport.ReindexLocation, _settings, [location]}
    assert location.translation_names == ["서울"]
  end
end
