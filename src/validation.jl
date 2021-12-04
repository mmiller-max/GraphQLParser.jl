"""
    is_valid_executable_document(str::String; throw_on_error=false)

Returns a `Bool` indicating whether the document described by `str` is valid.

The document is parsed and some validation performed.
For further information see [`validate_executable_document`](@ref) and package documentation.

To throw an exception if a validation error is found, set `throw_on_error` to `true`.
(Note, parsing errors will always throw an exception).

To retrieve a list of validation errors in the document, use [`validate_executable_document`](@ref) instead.
"""
function is_valid_executable_document(str::String; throw_on_error=false)
    errors = validate_executable_document(str)
    if throw_on_error && !isempty(errors)
        throw(ValidationException(errors))
    end
    return isempty(errors)
end

"""
    validate_executable_document(str::String)

Return a list of validation errors in the GraphQL executable document described by `str`.

Firstly the document will be parsed with any parsing errors being immediately thrown.

Secondly, the parsed document will be validated against **some** of the specification with all validation errors being returned.
See the package documentation for a full description of what validation is performed.
"""
validate_executable_document(str::String) = validate(parse(str))

function validate(doc::Document)
    errors = ValidationError[]
    validate_operations!(errors::Vector{ValidationError}, doc::Document)
    validate_fragments!(errors::Vector{ValidationError}, doc::Document)
end

function validate_operations!(errors::Vector{ValidationError}, doc::Document)
    defined_operations = [(name=def.name, loc=def.loc) for def in doc.definitions if isa(def, Operation)]
    defined_names = [def.name for def in defined_operations]
    n_defined_names = length(defined_names)

    for op in defined_operations
        # Check anonymouse operation is alone - 5.2.2.1
        if isnothing(op.name) && n_defined_names > 1
            push!(
                errors,
                AnonymousOperationNotAlone(
                    # TODO: message
                    "This anonymous operation must be the only defined operation.",
                    [op.loc]
                )
            )
        end
        # Check operation names are unique - 5.2.1.1
        if count(==(op.name), defined_names) > 1
            push!(
                errors,
                RepeatedOperationDefinition(
                    "There can only be one Operation named \"$(op.name)\".",
                    [op.loc]
                )
            )
        end
    end
    return errors
end

function validate_fragments!(errors::Vector{ValidationError}, doc::Document)
    defined_fragments = [(name=def.name, loc=def.loc) for def in doc.definitions if isa(def, FragmentDefinition)]
    defined_names = [def.name for def in defined_fragments]

    # Check for multiple definitions of same fragment - 5.5.1.1
    if length(defined_names) > length(unique(defined_names))
        for fragment in defined_fragments
            if count(==(fragment.name), defined_names) > 1
                push!(
                    errors,
                    RepeatedFragmentDefinition(
                        "There can only be one fragment named \"$(fragment.name))\".",
                        [fragment.loc]
                    )
                )
            end
        end
    end

    # Check all used fragments are defined - 5.5.1.4
    used_fragments = find_fragments(doc)
    used_names = keys(used_fragments)
    for (name, locs) in used_fragments
        if name ∉ defined_names
            push!(
                errors,
                UnknownFragment(
                    "Unknown fragment \"$name\"",
                    locs
                )
            )
        end
    end

    # Check all defined fragments are used - 5.5.2.1
    for fragment in defined_fragments
        if fragment.name ∉ used_names
            push!(
                errors,
                UnusedFragment(
                    "Fragment \"$(fragment.name)\" is never used.",
                    [fragment.loc]
                )
            )
        end
    end

    return errors
end

find_fragments(doc) = find_fragments!(Dict{String, Vector{Loc}}(), doc)
find_fragments!(used_fragments, doc::Document) = find_fragments!(used_fragments, doc.definitions)
find_fragments!(used_fragments, frag_def::FragmentDefinition) = find_fragments!(used_fragments, frag_def.selection_set)
find_fragments!(used_fragments, op::Operation) = find_fragments!(used_fragments, op.selection_set)
find_fragments!(used_fragments, ss::SelectionSet) = find_fragments!(used_fragments, ss.selections)
find_fragments!(used_fragments, field::Field) = find_fragments!(used_fragments, field.selection_set)
find_fragments!(used_fragments, inline_frag::InlineFragment) = find_fragments!(used_fragments, inline_frag.selection_set)
find_fragments!(used_fragments, objs::Vector) = (foreach((obj) -> find_fragments!(used_fragments, obj), objs); used_fragments)
find_fragments!(used_fragments, ::Nothing) = used_fragments
function find_fragments!(used_fragments, frag_spread::FragmentSpread)
    if haskey(used_fragments, frag_spread.name)
        push!(used_fragments[frag_spread.name], frag_spread.loc)
    else
        used_fragments[frag_spread.name] = [frag_spread.loc]
    end
    return used_fragments
end
