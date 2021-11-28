##########
# Values #
##########

@auto_hash_equals struct Variable
    name::String
end

@auto_hash_equals struct Alias
    alias::String
    name::String
end

@auto_hash_equals struct Enum
    name::String
end

@auto_hash_equals struct ObjectField
    name::String
    value
end

@auto_hash_equals struct InputObject
    object_fields::Vector{ObjectField}
end

#################
# SelectionSets #
#################

@auto_hash_equals struct Argument
    name::String
    value
end

@auto_hash_equals struct Directive
    name::String
    arguments::Union{Nothing, Vector{Argument}}
end

abstract type Selection end

@auto_hash_equals struct Field{T} <: Selection
    alias::Union{Nothing, String}
    name::String
    arguments::Union{Nothing, Vector{Argument}}
    directives
    selection_set::T # avoid circulat deps
end

struct Fragment <: Selection end

@auto_hash_equals struct SelectionSet
    selections::Vector{Selection}
end

@auto_hash_equals struct FragmentSpread <: Selection
    name::String
    directives::Union{Vector{Directive}, Nothing}
end

@auto_hash_equals struct InlineFragment <: Selection
    named_type::Union{String, Nothing}
    directives::Union{Vector{Directive}, Nothing}
    selection_set::SelectionSet
end

function print_selection(io, field::Field)
    !isnothing(field.alias) && print(io, field.alias, ": ")
    print(io, field.name)
    !isnothing(field.arguments) && print(io, "(args...)")
    !isnothing(field.directives) && print(io, "@...")
    !isnothing(field.selection_set) && print(io, "{selection_set...}")
end

function print_selection_set(io, selection_set::SelectionSet)
    print(io, "{\n")
    for selection in selection_set.selections
        print(io, "    ")
        print_selection(io, selection)
        print(io, "\n")
    end
    print(io, "}")
end
function Base.show(io::IO, ::MIME"text/plain", selection_set::SelectionSet)
    print_selection_set(io, selection_set)
end

@auto_hash_equals struct VariableDefinition
    name::String
    type::String
    value
    directive
end

###############
# Definitions #
###############

abstract type Definition end

@auto_hash_equals struct FragmentDefinition <: Definition
    name::String
    named_type::String
    directives::Union{Nothing, Vector{Directive}}
    selection_set::SelectionSet
end

@auto_hash_equals struct Operation <: Definition
    operation_type::String
    name::Union{Nothing, String}
    variable_definitions
    directives
    selection_set::SelectionSet
end

function Base.show(io::IO, ::MIME"text/plain", op::Operation)
    println(io, "Operation")
    print(io, "\n")
    print(io, "$(op.operation_type)")
    !isnothing(op.name) && print(io, " ", op.name)
    !isnothing(op.variable_definitions) && print(io, "(vars...)")
    !isnothing(op.directives) && print(io, "@...")
    print_selection_set(io, op.selection_set)
end

############
# Document #
############

@auto_hash_equals struct Document
    definitions::Vector{Definition}
end