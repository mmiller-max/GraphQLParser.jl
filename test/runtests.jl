using GraphQLParser
using GraphQLParser: Document, Operation, FragmentDefinition,
    Field, FragmentSpread, InlineFragment, SelectionSet, Variable,
    Argument, Directive, VariableDefinition
using Test

@testset "GraphQLParser.jl" begin
    include("parser_tests.jl")
end
