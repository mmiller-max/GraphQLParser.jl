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
    errors = GraphQLParser.validate_fragments!(GraphQLParser.ValidationError[], GraphQLParser.parse(str))
    @test only(errors) isa GraphQLParser.UnknownFragment
    @test only(errors[1].locations) == Loc(1, 24)

    str = """
    query myquery2{field{... on User {...TopLevel}}}
    query myquery3{field{... on User {...TopLevel}}}
    """
    errors = GraphQLParser.validate_fragments!(GraphQLParser.ValidationError[], GraphQLParser.parse(str))
    @test only(errors) isa GraphQLParser.UnknownFragment
    @test length(errors[1].locations) == 2
    @test errors[1].locations[1] == Loc(1, 38)
    @test errors[1].locations[2] == Loc(2, 38)

    # Counter Example 144
    str = """
    {
        dog {
            ...undefinedFragment
        }
    }
    """
    errors = GraphQLParser.validate_fragments!(GraphQLParser.ValidationError[], GraphQLParser.parse(str))
    @test only(errors) isa GraphQLParser.UnknownFragment
    @test only(errors[1].locations) == Loc(3, 12)

    str = """
    query myquery{field{...TopLevel}}
    
    query myquery{field{...TopLevel2}}

    query myquery2{field{... on User {...forInlineFragment}}}
    
    query myquery3{field{... on User {...forInlineFragment}}}

    fragment TopLevel2 on Name {...SubTopLevel}
    """
    errors = GraphQLParser.validate_fragments!(GraphQLParser.ValidationError[], GraphQLParser.parse(str))
    
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
    errors = GraphQLParser.validate_fragments!(GraphQLParser.ValidationError[], GraphQLParser.parse(str))
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
    errors = GraphQLParser.validate_fragments!(GraphQLParser.ValidationError[], GraphQLParser.parse(str))
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
    errors = GraphQLParser.validate_fragments!(GraphQLParser.ValidationError[], GraphQLParser.parse(str))
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