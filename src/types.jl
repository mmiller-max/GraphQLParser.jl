# Overarching parent type
abstract type GQLItem end

##########
# Values #
##########

struct Loc <: GQLItem
    line::Int
    column::Int
end

struct Variable <: GQLItem
    name::String
    loc::Loc
end
Variable(name) = Variable(name, Loc(0,0))
struct Alias # TODO: remove?
    alias::String
    name::String
    loc::Loc
end
Alias(alias, name) = Alias(alias, name, Loc(0,0))

struct Enum <: GQLItem
    name::String
    loc::Loc
end
Enum(name) = Enum(name, Loc(0,0))

struct ObjectField <: GQLItem
    name::String
    value
    loc::Loc
end
ObjectField(name, value) = ObjectField(name, value, Loc(0,0))

struct InputObject <: GQLItem
    object_fields::Vector{ObjectField}
    loc::Loc
end
InputObject(object_fields) = InputObject(object_fields, Loc(0,0))

#################
# SelectionSets #
#################

struct Argument <: GQLItem
    name::String
    value
    loc::Loc
end
Argument(name, value) = Argument(name, value, Loc(0,0))

struct Directive <: GQLItem
    name::String
    arguments::Union{Nothing, Vector{Argument}}
    loc::Loc
end
Directive(name, arguments) = Directive(name, arguments, Loc(0,0))

abstract type Selection  <: GQLItem end

struct Field{T} <: Selection
    alias::Union{Nothing, String}
    name::String
    arguments::Union{Nothing, Vector{Argument}}
    directives
    selection_set::T # avoid circular deps
    loc::Loc
end
Field(alias, name, args, dirs, ss) = Field(alias, name, args, dirs, ss, Loc(0,0))

struct Fragment <: Selection end

struct SelectionSet <: GQLItem
    selections::Vector{Selection}
    loc::Loc
end
SelectionSet(selections) = SelectionSet(selections, Loc(0,0))

struct FragmentSpread <: Selection
    name::String
    directives::Union{Vector{Directive}, Nothing}
    loc::Loc
end
FragmentSpread(name, directives) = FragmentSpread(name, directives, Loc(0,0))

struct InlineFragment <: Selection
    named_type::Union{String, Nothing}
    directives::Union{Vector{Directive}, Nothing}
    selection_set::SelectionSet
    loc::Loc
end
InlineFragment(name, dirs, ss) = InlineFragment(name, dirs, ss, Loc(0,0))

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

struct VariableDefinition <: GQLItem
    name::String
    type::String
    value
    directives::Union{Nothing, Vector{Directive}}
    loc::Loc
end
VariableDefinition(name, type, value, dirs) = VariableDefinition(name, type, value, dirs, Loc(0,0))

###############
# Definitions #
###############

abstract type Definition  <: GQLItem end

struct FragmentDefinition <: Definition
    name::String
    named_type::String
    directives::Union{Nothing, Vector{Directive}}
    selection_set::SelectionSet
    loc::Loc
end
FragmentDefinition(name, named_type, dirs, ss) = FragmentDefinition(name, named_type, dirs, ss, Loc(0,0))

struct Operation <: Definition
    operation_type::String
    name::Union{Nothing, String}
    variable_definitions::Union{Nothing, Vector{VariableDefinition}}
    directives::Union{Nothing, Vector{Directive}}
    selection_set::SelectionSet
    loc::Loc
end
Operation(op_type, named_type, var_defs, dirs, ss) = Operation(op_type, named_type, var_defs, dirs, ss, Loc(0,0))

function Base.show(io::IO, ::MIME"text/plain", op::Operation)
    println(io, "Operation")
    print(io, "\n")
    print(io, "$(op.operation_type)")
    !isnothing(op.name) && print(io, " ", op.name)
    !isnothing(op.variable_definitions) && print(io, "(vars...)")
    !isnothing(op.directives) && print(io, "@...")
    print_selection_set(io, op.selection_set)
end

function Base.:(==)(n1::T, n2:: T) where T <: GQLItem
    for name in fieldnames(T)
        if name != :loc
            !isequal(getproperty(n1, name), getproperty(n2, name)) && return false
        end
    end
    return true
end

function Base.hash(n::GQLItem, h::UInt)
    for name in fieldnames(T)
        if name != :loc
            h = hash(getproperty(n, name), h)
        end
    end
    return h
end

############
# Document #
############

struct Document <: GQLItem
    definitions::Vector{Definition}
end