```@meta
CurrentModule = GraphQLParser
```

# GraphQLParser

*A Julia package to parse and validate GraphQL executable documents*

Documentation for [GraphQLParser](https://github.com/mmiller-max/GraphQLParser.jl).
## Installation

The package can be installed with Julia's package manager,
either by using the Pkg REPL mode (press `]` to enter):
```
pkg> add GraphQLParser
```
or by using Pkg functions
```julia-repl
julia> using Pkg; Pkg.add("GraphQLParser")
```

## Use

This package can be used to check whether a document is valid

```julia
using GraphQLParser

document = """
query myQuery{
    findDog
}
"""

is_valid_executable_document(document)
# true
```

Or return a list of validation errors

```julia
using GraphQLParser

document = """
query myQuery{
    findDog
}

query myQuery{
    findCat
}
"""

errors = validate_executable_document(document)
errors[1]
# GQLError
#       message: There can only be one Operation named "myQuery".
#      location: Line 1 Column 1
errors[2]
# GQLError
#       message: There can only be one Operation named "myQuery".
#      location: Line 5 Column 1
```

## Validation

[`validate_executable_document`](@ref) performs validation that does not require the schema and therefore does not fully validate the document as per the GraphQL specification.
The validation performed includes:

- [5.2.1.1 Named operation uniqueness](https://spec.graphql.org/October2021/#sec-Named-Operation-Definitions)
- [5.2.2.1 Lone anonymous operation](https://spec.graphql.org/October2021/#sec-Anonymous-Operation-Definitions)
- [5.5.1.1 Fragment name uniqueness](https://spec.graphql.org/October2021/#sec-Fragment-Name-Uniqueness)
- [5.5.1.4 Fragments must be used](https://spec.graphql.org/October2021/#sec-Fragments-Must-Be-Used)
- [5.5.2.1 Fragment spread target defined](https://spec.graphql.org/October2021/#sec-Fragment-spread-target-defined)
