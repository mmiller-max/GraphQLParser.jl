using GraphQLParser
using GraphQLParser: Document, Operation, FragmentDefinition,
    Field, FragmentSpread, InlineFragment, SelectionSet, Variable,
    Argument, Directive, VariableDefinition, Loc
using Test

@testset "GraphQLParser.jl" begin
    include("parser_tests.jl")
    include("validation.jl")
end
