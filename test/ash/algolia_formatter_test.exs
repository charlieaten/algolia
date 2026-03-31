defmodule Ash.AlgoliaFormatterTest do
  use ExUnit.Case, async: true

  test "formats algolia setting builders in ash style" do
    opts = Code.eval_file(".formatter.exs") |> elem(0)

    input = """
    defmodule Demo do
      use Ash.Resource,
        data_layer: Ash.DataLayer.Ets,
        extensions: [Ash.Algolia]

      algolia do
        index(:venues) do
          projection() do
            object_id(:slug)
            load([:author, :tags])
            field(:title)
            field(:body, &String.upcase/1)
            compute(:author_name, & &1.author.name)

            compute(:tag_names, fn venue ->
              Enum.map(venue.tags || [], & &1.name)
            end)
          end

          settings do
            attributes_for_faceting([:location])
            hits_per_page(12)
          end
        end
      end
    end
    """

    formatted =
      input
      |> Spark.Formatter.format(opts)
      |> Ash.Algolia.Formatter.format(opts)

    assert formatted =~ "index :venues do"
    assert formatted =~ "projection do"
    assert formatted =~ "object_id :slug"
    assert formatted =~ "load [:author, :tags]"
    assert formatted =~ "field :title"
    assert formatted =~ "field :body, &String.upcase/1"
    assert formatted =~ "compute :author_name, & &1.author.name"
    assert formatted =~ "compute :tag_names,"
    assert formatted =~ "fn venue ->"
    assert formatted =~ "attributes_for_faceting [:location]"
    assert formatted =~ "hits_per_page 12"

    refute formatted =~ "index(:venues)"
    refute formatted =~ "projection() do"
    refute formatted =~ "object_id(:slug)"
    refute formatted =~ "load([:author, :tags])"
    refute formatted =~ "field(:title)"
    refute formatted =~ "field(:body, &String.upcase/1)"
    refute formatted =~ "compute(:author_name, & &1.author.name)"
    refute formatted =~ "attributes_for_faceting([:location])"
    refute formatted =~ "hits_per_page(12)"
  end

  test "does not rewrite matching calls outside the algolia dsl" do
    opts = Code.eval_file(".formatter.exs") |> elem(0)

    input = """
    defmodule Demo do
      def attributes do
        attributes_for_faceting([:location])
      end
    end
    """

    formatted = Ash.Algolia.Formatter.format(input, opts)

    assert formatted =~ "attributes_for_faceting([:location])"
  end
end
