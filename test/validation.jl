@testset "Fragment validation" begin
    str = """
    query myquery{field{...TopLevel}}

    query myquery2{field{... on User {...forInlineFragment}}}

    fragment TopLevel on Name {...SubTopLevel}

    fragment SubTopLevel on Name {field}

    fragment forInlineFragment on Name {field}
    """

    frags = GraphQLParser.find_fragments(GraphQLParser.parse(str))
    for name in ("forInlineFragment", "TopLevel", "SubTopLevel")
        @test haskey(frags, name)
    end

    str = """
    query myquery{field{...TopLevel}}
    """
    errors = GraphQLParser.validate(GraphQLParser.parse(str))
    @test only(errors) isa GraphQLParser.UnknownFragment
    @test only(errors[1].locations) == Loc(1, 24)

    str = """
    query myquery2{field{... on User {...TopLevel}}}
    """
    errors = GraphQLParser.validate(GraphQLParser.parse(str))
    @test only(errors) isa GraphQLParser.UnknownFragment
    @test errors[1].locations[1] == Loc(1, 38)

    # Counter Example 144
    str = """
    {
        dog {
            ...undefinedFragment
        }
    }
    """
    errors = GraphQLParser.validate_operations!(GraphQLParser.ValidationError[], GraphQLParser.parse(str))
    @test only(errors) isa GraphQLParser.UnknownFragment
    @test only(errors[1].locations) == Loc(3, 12)

    str = """
    query myquery1{field{...TopLevel}}
    
    query myquery2{field{...TopLevel2}}

    query myquery3{field{... on User {...forInlineFragment}}}
    
    fragment TopLevel2 on Name {...SubTopLevel}
    """
    errors = GraphQLParser.validate(GraphQLParser.parse(str))
    
    @test length(errors) == 3
    @test all(err -> isa(err, GraphQLParser.UnknownFragment), errors)

    # Example 137
    str = """
    {
        dog {
            ...fragmentOne
            ...fragmentTwo
        }
    }

    fragment fragmentOne on Dog {
        name
    }

    fragment fragmentTwo on Dog {
        owner {
            name
        }
    }
    """
    errors = GraphQLParser.validate(GraphQLParser.parse(str))
    @test isempty(errors)
    
    # Counter Example 138
    str = """
    {
        dog {
            ...fragmentOne
        }
    }

    fragment fragmentOne on Dog {
        name
    }

    fragment fragmentOne on Dog {
        owner {
            name
        }
    }
    """
    errors = GraphQLParser.validate(GraphQLParser.parse(str))
    @test length(errors) == 2
    @test errors[1] isa GraphQLParser.RepeatedFragmentDefinition
    @test errors[2] isa GraphQLParser.RepeatedFragmentDefinition

    # Counter Example 143
    str = """
    fragment nameFragment on Dog { # unused
        name
    }

    {
        dog {
            name
        }
    }
    """
    errors = GraphQLParser.validate(GraphQLParser.parse(str))
    @test only(errors) isa GraphQLParser.UnusedFragment
end

@testset "Operations" begin
    @testset "5.2.1.1 Operation Name Uniqueness" begin
        # Example 103
        str = """
        query getDogName {
            dog {
                name
            }
        }
            
        query getOwnerName {
            dog {
                owner {
                    name
                }
            }
        }
        """
        errors = GraphQLParser.validate_operations!(GraphQLParser.ValidationError[], GraphQLParser.parse(str))
        @test isempty(errors)

        # Counter Example 104
        str = """
        query getName {
            dog {
                name
            }
        }
        
        query getName {
            dog {
                owner {
                    name
                }
            }
        }
        """
        errors = GraphQLParser.validate_operations!(GraphQLParser.ValidationError[], GraphQLParser.parse(str))
        @test length(errors) == 2
        @test errors[1] isa GraphQLParser.RepeatedOperationDefinition
        @test errors[2] isa GraphQLParser.RepeatedOperationDefinition
        @test errors[1].locations == [Loc(1,1)]
        @test errors[2].locations == [Loc(7,1)]

        # Counter Example 105
        str = """
        query dogOperation {
            dog {
                name
            }
        }
        
        mutation dogOperation {
            mutateDog {
                id
            }     
        }
        """
        errors = GraphQLParser.validate_operations!(GraphQLParser.ValidationError[], GraphQLParser.parse(str))
        @test length(errors) == 2
        @test errors[1] isa GraphQLParser.RepeatedOperationDefinition
        @test errors[2] isa GraphQLParser.RepeatedOperationDefinition
        @test errors[1].locations == [Loc(1,1)]
        @test errors[2].locations == [Loc(7,1)]
    end

    @testset "5.2.2.1 Lone Anonymous Operation" begin
        # Example 106
        str = """
        {
            dog {
                name
            }
        }
        """
        errors = GraphQLParser.validate_operations!(GraphQLParser.ValidationError[], GraphQLParser.parse(str))
        @test isempty(errors)

        # Counter Example 107
        str = """
        {
            dog {
                name
            }
        }

        query getName {
            dog {
                owner {
                    name
                }
            }
        }
        """
        errors = GraphQLParser.validate_operations!(GraphQLParser.ValidationError[], GraphQLParser.parse(str))
        @test only(errors) isa GraphQLParser.AnonymousOperationNotAlone
        @test errors[1].locations[1] == Loc(1,1)
    end
end

@testset "Variables" begin
    # Counter Example 165
    str = """
    query houseTrainedQuery(\$atOtherHomes: Boolean, \$atOtherHomes: Boolean) {
        dog {
            isHouseTrained(atOtherHomes: \$atOtherHomes)
        }
    }
    """
    errors = GraphQLParser.validate_operations!(GraphQLParser.ValidationError[], GraphQLParser.parse(str))
    @test length(errors) == 2
    @test errors[1] isa GraphQLParser.RepeatedVariableDefinition
    @test errors[2] isa GraphQLParser.RepeatedVariableDefinition

    # Example 166
    str = """
    query A(\$atOtherHomes: Boolean) {
        ...HouseTrainedFragment
    }

    query B(\$atOtherHomes: Boolean) {
        ...HouseTrainedFragment
    }

    fragment HouseTrainedFragment on Query {
        dog {
            isHouseTrained(atOtherHomes: \$atOtherHomes)
        }
    }
    """
    @test GraphQLParser.is_valid_executable_document(str)

    # Example 170
    str = """
    query variableIsDefined(\$atOtherHomes: Boolean) {
        dog {
            isHouseTrained(atOtherHomes: \$atOtherHomes)
        }
    }
    """
    @test GraphQLParser.is_valid_executable_document(str)

    # Counter Example 171
    str = """
    query variableIsNotDefined {
        dog {
            isHouseTrained(atOtherHomes: \$atOtherHomes)
        }
    }
    """
    errors = GraphQLParser.validate_executable_document(str)
    @test only(errors) isa GraphQLParser.UnknownVariable

    # Example 172
    str = """
    query variableIsDefinedUsedInSingleFragment(\$atOtherHomes: Boolean) {
        dog {
            ...isHouseTrainedFragment
        }
    }
    
    fragment isHouseTrainedFragment on Dog {
        isHouseTrained(atOtherHomes: \$atOtherHomes)
    }
    """
    @test GraphQLParser.is_valid_executable_document(str)

    # Counter Example 173
    str = """
    query variableIsNotDefinedUsedInSingleFragment {
        dog {
            ...isHouseTrainedFragment
        }
    }

    fragment isHouseTrainedFragment on Dog {
        isHouseTrained(atOtherHomes: \$atOtherHomes)
    }
    """
    errors = GraphQLParser.validate_executable_document(str)
    @test only(errors) isa GraphQLParser.UnknownVariable

    # Counter Example 174
    str = """
    query variableIsNotDefinedUsedInNestedFragment {
        dog {
            ...outerHouseTrainedFragment
        }
    }

    fragment outerHouseTrainedFragment on Dog {
        ...isHouseTrainedFragment
    }

    fragment isHouseTrainedFragment on Dog {
        isHouseTrained(atOtherHomes: \$atOtherHomes)
    }
    """
    errors = GraphQLParser.validate_executable_document(str)
    @test only(errors) isa GraphQLParser.UnknownVariable

    # Example 175
    str = """
    query houseTrainedQueryOne(\$atOtherHomes: Boolean) {
        dog {
            ...isHouseTrainedFragment
        }
    }

    query houseTrainedQueryTwo(\$atOtherHomes: Boolean) {
        dog {
            ...isHouseTrainedFragment
        }
    }

    fragment isHouseTrainedFragment on Dog {
        isHouseTrained(atOtherHomes: \$atOtherHomes)
    }
    """
    @test GraphQLParser.is_valid_executable_document(str)

    # Counter Example 176
    str = """
    query houseTrainedQueryOne(\$atOtherHomes: Boolean) {
        dog {
            ...isHouseTrainedFragment
        }
    }

    query houseTrainedQueryTwoNotDefined {
        dog {
            ...isHouseTrainedFragment
        }
    }

    fragment isHouseTrainedFragment on Dog {
        isHouseTrained(atOtherHomes: \$atOtherHomes)
    }
    """
    errors = GraphQLParser.validate_executable_document(str)
    @test only(errors) isa GraphQLParser.UnknownVariable

    # Counter Example 177
    str = """
        query variableUnused(\$atOtherHomes: Boolean) {
        dog {
            isHouseTrained
        }
    }
    """
    errors = GraphQLParser.validate_executable_document(str)
    @test only(errors) isa GraphQLParser.UnusedVariable

    # Example 178
    str = """
    query variableUsedInFragment(\$atOtherHomes: Boolean) {
        dog {
            ...isHouseTrainedFragment
        }
    }
    
    fragment isHouseTrainedFragment on Dog {
        isHouseTrained(atOtherHomes: \$atOtherHomes)
    }
    """
    @test GraphQLParser.is_valid_executable_document(str)

    # Counter Example 179
    str = """
    query variableNotUsedWithinFragment(\$atOtherHomes: Boolean) {
        dog {
            ...isHouseTrainedWithoutVariableFragment
        }
    }

    fragment isHouseTrainedWithoutVariableFragment on Dog {
        isHouseTrained
    }
    """
    errors = GraphQLParser.validate_executable_document(str)
    @test only(errors) isa GraphQLParser.UnusedVariable

    # Counter Example № 180
    str = """
    query queryWithUsedVar(\$atOtherHomes: Boolean) {
        dog {
            ...isHouseTrainedFragment
        }
    }
    
    query queryWithExtraVar(\$atOtherHomes: Boolean, \$extra: Int) {
        dog {
            ...isHouseTrainedFragment
        }
    }
    
    fragment isHouseTrainedFragment on Dog {
        isHouseTrained(atOtherHomes: \$atOtherHomes)
    }
    """
    errors = GraphQLParser.validate_executable_document(str)
    @test only(errors) isa GraphQLParser.UnusedVariable
end

@testset "Directives" begin
    # Counter Example 163
    str = """
    query (\$foo: Boolean = true, \$bar: Boolean = false) {
        field @skip(if: \$foo) @skip(if: \$bar)
    }
    """
    doc = GraphQLParser.parse(str)
    errors = GraphQLParser.validate_operations!(GraphQLParser.ValidationError[], GraphQLParser.parse(str))
    @test only(errors) isa GraphQLParser.RepeatedDirectiveName

    # Example 164
    str = """
    query (\$foo: Boolean = true, \$bar: Boolean = false) {
        field @skip(if: \$foo) {
            subfieldA
        }
        field @skip(if: \$bar) {
            subfieldB
        }
    }
    """
    doc = GraphQLParser.parse(str)
    errors = GraphQLParser.validate_operations!(GraphQLParser.ValidationError[], GraphQLParser.parse(str))
    @test isempty(errors)
end

@testset "Input Objects" begin
    # Counter Example № 161
    str = """ {
        field(arg: { field: true, field: false })
    }
    """
    errors = GraphQLParser.validate_executable_document(str)
    @test only(errors) isa GraphQLParser.RepeatedInputObjectField
end