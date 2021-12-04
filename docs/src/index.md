```@meta
CurrentModule = GraphQLParser
```

# GraphQLParser

Documentation for [GraphQLParser](https://github.com/mmiller-max/GraphQLParser.jl).

```@index
```

```@autodocs
Modules = [GraphQLParser]
```

## Validation

`validate_executable_document` performs validation that does not require the schema and therefore does not fully validate the document as per the GraphQL specification.
The validation includes:

- [5.2.1.1 Named Operation Uniqueness](https://spec.graphql.org/October2021/#sec-Named-Operation-Definitions)
- [5.2.2.1 Lone Anonymous Operation](https://spec.graphql.org/October2021/#sec-Anonymous-Operation-Definitions)
- [5.5.1.1 Fragment Name Uniqueness](https://spec.graphql.org/October2021/#sec-Fragment-Name-Uniqueness)
- [5.5.1.4 Fragments Must Be Used](https://spec.graphql.org/October2021/#sec-Fragments-Must-Be-Used)
= [5.5.2.1 Fragment spread target defined](https://spec.graphql.org/October2021/#sec-Fragment-spread-target-defined)



