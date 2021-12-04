"""
    ValidationError

Abstract type for validation errors.
"""
abstract type ValidationError end

errors = (
    :UnknownFragment,
    :UnusedFragment,
    :RepeatedFragmentDefinition,
    :RepeatedOperationDefinition,
    :AnonymousOperationNotAlone
)
for err in errors
    @eval begin
        Base.@kwdef struct $err <: ValidationError
            message::String
            locations::Union{Vector{Loc}, Nothing} = nothing
        end
    end
end

function Base.show(io::IO, ::MIME"text/plain", err::ValidationError)
    printstyled(io, "GQLError", color=Base.error_color())
    printstyled(io, "\n      message: ", err.message, color=Base.error_color())
    if !isnothing(err.locations)
        printstyled(io, "\n  location(s): $(err.locations[1])", color=Base.error_color())
        for i in 2:length(err.locations)
            printstyled(io, "\n               $(err.locations[i])", color=Base.error_color())
        end
    end
end