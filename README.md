# GraphQLParser

Parses a GraphQL query string into a nested struture of types. Follows the [2021 specification](https://spec.graphql.org/October2021).

Does not perform any interaction with the server, so no input coercion or any checking, other than checking that the query string is valid.

Mostly just an attempt to see how easy this would be, but potentially has some uses in other GraphQL packages.

