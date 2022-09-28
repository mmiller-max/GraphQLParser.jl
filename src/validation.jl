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
    return errors
end

validate_variable_definitions!(errors, ::Nothing, used_variables, op) = errors
function validate_variable_definitions!(errors, var_defs::Vector{VariableDefinition}, used_variables, op::Operation)
    variable_names = (var_def.name for var_def in var_defs)
    for var_def in var_defs
        if count(==(var_def.name), variable_names) > 1
            push!(
                errors,
                RepeatedVariableDefinition(
                    "There can only be one variable named \"$(var_def.name)\".",
                    [var_def.loc]
                )
            )
        end
        if var_def.name ∉ used_variables
            push!(
                errors,
                UnusedVariable(
                    "Variable \"$(var_def.name)\" is never used in operation \"$(op.name)\".",
                    [var_def.loc, op.loc]
                )
            )
        end
    end
    return errors
end

function validate_operation!(errors, op::Operation, defined_fragments)
    used_variables = String[]
    validate_directive_uniqueness!(errors, op.directives)
    validate_arguments!(errors, used_variables, op.directives, op)
    validate_selection_set!(errors, used_variables, op.selection_set, op, defined_fragments)
    validate_variable_definitions!(errors, op.variable_definitions, used_variables, op)
    return errors
end

validate_selection_set!(errors, used_variables, ::Nothing, op::Operation, defined_fragments) = errors
function validate_selection_set!(errors, used_variables, ss::SelectionSet, op::Operation, defined_fragments)
    for selection in ss.selections
        selection isa FragmentSpread && validate_fragment_spread!(errors, used_variables, selection, op, defined_fragments)
        selection isa InlineFragment && validate_inline_fragment!(errors, used_variables, selection, op, defined_fragments)
        selection isa Field && validate_field!(errors, used_variables, selection, op, defined_fragments)
    end
    # validate merging of fields
    return errors
end

function validate_fragment_spread!(errors, used_variables, spread::FragmentSpread, op::Operation, defined_fragments)
    if isnothing(defined_fragments) || isnothing(findfirst(def -> (def.name==spread.name), defined_fragments))
        push!(
            errors,
            UnknownFragment(
                "Unknown fragment \"$(spread.name)\"",
                [spread.loc]
            )
        )
        return errors
    end
    fragment_definition = defined_fragments[findfirst(def -> (def.name==spread.name), defined_fragments)]
    validate_arguments!(errors, used_variables, fragment_definition, op)
    validate_selection_set!(errors, used_variables, fragment_definition.selection_set, op, defined_fragments)
    # Don't need to check directive Uniqueness here as that is done at fragment definition
    return errors
end

function validate_inline_fragment!(errors, used_variables, inline_frag::InlineFragment, op::Operation, defined_fragments)
    validate_arguments!(errors, used_variables, inline_frag, op)
    validate_directive_uniqueness!(errors, inline_frag.directives)
    validate_selection_set!(errors, used_variables, inline_frag.selection_set, op, defined_fragments)
    return errors
end

validate_field!(errors, used_variables, ::Nothing, op::Operation, defined_fragments) = errors
function validate_field!(errors, used_variables, field::Field, op::Operation, defined_fragments)
    # Validate arguments
    validate_arguments!(errors, used_variables, field.arguments, op)
    # Validate directives
    validate_arguments!(errors, used_variables, field.directives, op)
    validate_directive_uniqueness!(errors, field.directives)

    # validate selection set
    validate_selection_set!(errors, used_variables, field.selection_set, op, defined_fragments)
    return errors
end

validate_directive_uniqueness!(errors, ::Nothing) = errors
function validate_directive_uniqueness!(errors, directives::Vector{Directive})
    directive_names = (directive.name for directive in directives)
    for directive in unique(x -> x.name, directives)
        if count(==(directive.name), directive_names) > 1
            push!(
                errors,
                RepeatedDirectiveName(
                    "The directive \"$(directive.name)\" can only be used once at this location.",
                    [dir.loc for dir in directives if dir.name == directive.name]
                )
            )
        end
    end
    return errors
end

validate_arguments!(errors, used_variables, ::Nothing, op::Operation) = errors
function validate_arguments!(errors, used_variables, fragment::Union{FragmentDefinition, InlineFragment}, op::Operation)
    validate_arguments!(errors, used_variables, fragment.directives, op)
    return errors
end
function validate_arguments!(errors, used_variables, directives::Vector{Directive}, op::Operation)
    for directive in directives
        validate_arguments!(errors, used_variables, directive.arguments, op)
    end
    return errors
end
function validate_arguments!(errors, used_variables, arguments::Vector{Argument}, op::Operation)
    argument_names = (argument.name for argument in arguments)
    for argument in arguments
        if count(==(argument.name), argument_names) > 1
            push!(
                errors,
                RepeatedArgumentName(
                    "There can only be one argument named \"$(op.name)\".",
                    [op.loc]
                )
            )
        end
        if argument.value isa Variable
            var = argument.value
            if isnothing(op.variable_definitions) || !any(==(var.name), (def.name for def in op.variable_definitions))
                push!(
                    errors,
                    UnknownVariable(
                        "Variable \"\$$(var.name)\" is not defined by operation \"$(op.name)\".",
                        [var.loc, op.loc]
                    )
                )
            end
            push!(used_variables, var.name)
        elseif argument.value isa InputObject
            input_object = argument.value
            field_names = (field.name for field in input_object.object_fields)
            for field in unique(x -> x.name, input_object.object_fields)
                if count(==(field.name), field_names) > 1
                    push!(
                        errors,
                        RepeatedInputObjectField(
                            "There can only be one input object field named \"$(field.name)\".",
                            [f.loc for f in input_object.object_fields if f.name == field.name]
                        )
                    )
                end
            end
        end
    end
    return errors
end

"""
    get_defined_operations(doc::Document)

Returns a generator over all operations that are defined in the document.
"""
get_defined_operations(doc::Document) = (def for def in doc.definitions if isa(def, Operation))

function validate_operations!(errors::Vector{ValidationError}, doc::Document)
    defined_operations = get_defined_operations(doc)
    defined_names = [def.name for def in defined_operations]
    n_defined_names = length(defined_names)

    defined_fragments = get_defined_fragments(doc) 
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
        validate_operation!(errors, op, defined_fragments)
    end

    return errors
end

"""
    get_defined_fragments(doc::Document)

Returns a vector of all fragments that are defined in the document.
"""
get_defined_fragments(doc::Document) = [def for def in doc.definitions if isa(def, FragmentDefinition)]

function validate_fragments!(errors::Vector{ValidationError}, doc::Document)
    defined_fragments = get_defined_fragments(doc)
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

    # Check all defined fragments are used - 5.5.2.1
    used_fragments = find_fragments(doc)
    used_names = keys(used_fragments)
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
        validate_directive_uniqueness!(errors, fragment.directives)
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
