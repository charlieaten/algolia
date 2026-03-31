defmodule Ash.Algolia.Formatter do
  @moduledoc false

  @behaviour Mix.Tasks.Format

  alias Spark.Dsl.{Entity, Section}

  @impl true
  def features(_opts), do: [extensions: [".ex", ".exs"]]

  @impl true
  def format(contents, opts) do
    case parse(contents) do
      {:ok, ast} ->
        case rewrite_algolia_sections(ast) do
          {new_ast, true} ->
            Sourceror.to_string(new_ast, formatter_opts(opts))

          {_ast, false} ->
            contents
        end

      :error ->
        contents
    end
  end

  defp parse(contents) do
    {:ok, Sourceror.parse_string!(contents)}
  rescue
    _ -> :error
  end

  defp rewrite_algolia_sections(ast) do
    Enum.reduce(Ash.Algolia.sections(), {ast, false}, fn %Section{} = section,
                                                         {quoted, changed?} ->
      Macro.prewalk(quoted, changed?, fn
        {name, _meta, _args} = node, acc when name == section.name ->
          {new_node, node_changed?} = rewrite_section(node, section)
          {new_node, truthy?(acc) or truthy?(node_changed?)}

        node, acc ->
          {node, acc}
      end)
    end)
  end

  defp rewrite_section({name, meta, args}, %Section{} = section) do
    {new_args, changed?} =
      rewrite_level_args(args, section_level_builders(section), section_children(section))

    {{name, meta, new_args}, changed?}
  end

  defp rewrite_entity({name, meta, args}, %Entity{} = entity) do
    {new_args, changed?} =
      rewrite_level_args(args, entity_level_builders(entity), entity_children(entity))

    {{name, meta, new_args}, changed?}
  end

  defp rewrite_level_args(args, builders, children) when is_list(args) do
    Enum.map_reduce(args, false, fn
      kw, changed? when is_list(kw) ->
        {new_kw, kw_changed?} =
          Enum.map_reduce(kw, false, fn
            {{:__block__, block_meta, [:do]}, {:__block__, body_meta, body_exprs}},
            inner_changed? ->
              {new_body_exprs, body_changed?} =
                Enum.map_reduce(body_exprs, false, fn expr, expr_changed? ->
                  {new_expr, rewritten?} =
                    rewrite_expr_at_level(expr, builders, children)

                  {new_expr, truthy?(expr_changed?) or truthy?(rewritten?)}
                end)

              new_kw_entry =
                {{:__block__, block_meta, [:do]}, {:__block__, body_meta, new_body_exprs}}

              {new_kw_entry, truthy?(inner_changed?) or truthy?(body_changed?)}

            {{:__block__, block_meta, [:do]}, single_expr}, inner_changed? ->
              {new_expr, expr_changed?} =
                rewrite_expr_at_level(single_expr, builders, children)

              {{{:__block__, block_meta, [:do]}, new_expr},
               truthy?(inner_changed?) or truthy?(expr_changed?)}

            other, inner_changed? ->
              {other, inner_changed?}
          end)

        {new_kw, truthy?(changed?) or truthy?(kw_changed?)}

      other, changed? ->
        {other, changed?}
    end)
  end

  defp rewrite_level_args(args, _builders, _children), do: {args, false}

  defp rewrite_expr_at_level({func, meta, args}, builders, children) when is_atom(func) do
    arg_count = Enum.count(List.wrap(args))

    meta_changed? =
      builders
      |> Keyword.get_values(func)
      |> Enum.any?(&(&1 in [arg_count, arg_count - 1])) and
        Keyword.keyword?(meta) and not is_nil(meta[:closing])

    new_meta =
      if meta_changed? do
        Keyword.delete(meta, :closing)
      else
        meta
      end

    {new_args, nested_changed?} =
      case Map.get(children, func) do
        {:section, %Section{} = section} ->
          rewrite_level_args(args, section_level_builders(section), section_children(section))

        {:entity, %Entity{} = entity} ->
          rewrite_entity({func, new_meta, args}, entity)
          |> case do
            {{^func, _entity_meta, entity_args}, changed?} -> {entity_args, changed?}
          end

        nil ->
          {args, false}
      end

    {{func, new_meta, new_args}, truthy?(meta_changed?) or truthy?(nested_changed?)}
  end

  defp rewrite_expr_at_level(node, _builders, _children), do: {node, false}

  defp section_level_builders(%Section{} = section) do
    section_option_builders(section) ++
      Enum.flat_map(section.entities, fn %Entity{} = entity ->
        child_builder_arities(entity)
      end)
  end

  defp entity_level_builders(%Entity{} = entity) do
    entity_option_builders(entity) ++
      Enum.flat_map(all_nested_entities(entity), &child_builder_arities/1)
  end

  defp section_children(%Section{} = section) do
    entity_map = Map.new(section.entities, &{&1.name, {:entity, &1}})
    section_map = Map.new(section.sections, &{&1.name, {:section, &1}})
    Map.merge(entity_map, section_map)
  end

  defp entity_children(%Entity{} = entity) do
    entity
    |> all_nested_entities()
    |> Map.new(&{&1.name, {:entity, &1}})
  end

  defp section_option_builders(%Section{} = section) do
    Enum.map(section.schema, fn {key, _schema} -> {key, 1} end)
  end

  defp entity_option_builders(%Entity{} = entity) do
    required_arg_names = required_arg_names(entity)

    entity.schema
    |> Keyword.drop(required_arg_names)
    |> Enum.map(fn {key, _schema} -> {key, 1} end)
  end

  defp child_builder_arities(%Entity{} = entity) do
    arg_count = Enum.count(List.wrap(entity.args))
    required_arg_count = Enum.count(List.wrap(entity.args), &match?(arg when is_atom(arg), &1))

    Enum.flat_map(required_arg_count..arg_count, fn arity ->
      [{entity.name, arity}, {entity.name, arity + 1}]
    end)
  end

  defp all_nested_entities(%Entity{} = entity) do
    Enum.flat_map(entity.entities, fn {_name, nested_entities} ->
      List.wrap(nested_entities)
    end)
  end

  defp required_arg_names(%Entity{} = entity) do
    Enum.flat_map(List.wrap(entity.args), fn
      arg when is_atom(arg) -> [arg]
      {arg, _opts} when is_atom(arg) -> [arg]
      _ -> []
    end)
  end

  defp formatter_opts(opts) do
    [
      locals_without_parens: Keyword.get(opts, :locals_without_parens, []),
      line_length: Keyword.get(opts, :line_length, 98)
    ]
  end

  defp truthy?(value), do: value not in [false, nil]
end
