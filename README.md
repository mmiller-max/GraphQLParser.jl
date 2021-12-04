# GraphQLParser

*A Julia package to parse and validate GraphQL executable documents*

[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://mmiller-max.github.io/GraphQLParser.jl/dev)
[![Build Status](https://github.com/mmiller-max/GraphQLParser.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/mmiller-max/GraphQLParser.jl/actions/workflows/CI.yml?query=branch%3Amain)
[![Coverage](https://codecov.io/gh/mmiller-max/GraphQLParser.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/mmiller-max/GraphQLParser.jl)

Parses a GraphQL executable document (that is, a query string) and partially validates it. Follows the [2021 specification](https://spec.graphql.org/October2021).

Why only partial validation? Full validation (as per the GraphQL specification) requies knowledge of the schema, and GraphQLParser assumes no knowledge of the server and will therefore only perform some validation.

For example, the validation provided by this package will fail if parsing fields, or if two variable definitions use the same name, but will not fail if a field is incorrectly named for a particularly query.
For more information about what is covered, see the documentation.

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