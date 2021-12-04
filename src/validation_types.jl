"""
    Error

Struct to contain information for errors recieved from the GraphQL server.
"""
abstract type Error end

errors = (
    :UnknownFragment,
    :UnusedFragment,
    :RepeatedFragmentDefinition,
    :RepeatedOperationDefinition,
    :AnonymousOperationNotAlone
)
for err in errors
    @eval begin
        Base.@kwdef struct $err <: Error
            message::String
            locations::Union{Vector{Loc}, Nothing} = nothing
        end
    end
end

function Base.show(io::IO, ::MIME"text/plain", err::Error)
    printstyled(io, "GQLError", color=Base.error_color())
    printstyled(io, "\n      message: ", err.message, color=Base.error_color())
    if !isnothing(err.locations)
        printstyled(io, "\n  location(s): $(err.locations[1])", color=Base.error_color())
        for i in 2:length(err.locations)
            printstyled(io, "\n               $(err.locations[i])", color=Base.error_color())
        end
    end
end