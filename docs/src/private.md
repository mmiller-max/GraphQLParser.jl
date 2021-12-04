# Private

Package internals documentation.

## Parsing

Parsing is currently part of the private API as the output types are liable to change. Once this has stabilised, this will move to the public API.

```@docs
GraphQLParser.parse
```

## Miscellaneous

```@autodocs
Modules = [GraphQLParser]
Filter = t -> !in(t, (GraphQLParser.parse,))
Public = false
```