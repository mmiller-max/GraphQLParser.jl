using GraphQLParser
using Documenter

DocMeta.setdocmeta!(GraphQLParser, :DocTestSetup, :(using GraphQLParser); recursive=true)

makedocs(;
    modules=[GraphQLParser],
    authors="Mal Miller and contributors",
    repo="https://github.com/mmiller-max/GraphQLParser.jl/blob/{commit}{path}#{line}",
    sitename="GraphQLParser.jl",
    format=Documenter.HTML(;
        prettyurls=get(ENV, "CI", "false") == "true",
        canonical="https://mmiller-max.github.io/GraphQLParser.jl",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
        "Library" => [
            "Public" => "public.md",
            "Private" => "private.md",
        ]
    ],
)

deploydocs(;
    repo="github.com/mmiller-max/GraphQLParser.jl",
    devbranch="main",
)
