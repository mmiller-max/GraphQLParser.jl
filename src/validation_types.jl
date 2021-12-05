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
    :AnonymousOperationNotAlone,
    :RepeatedVariableDefinition,
    :RepeatedArgumentName,
    :UnknownVariable,
    :UnusedVariable,
    :RepeatedDirectiveName,
    :RepeatedInputObjectField,
)
for err in errors
    @eval begin
        Base.@kwdef struct $err <: ValidationError
            message::String
            locations::Union{Vector{Loc}, Nothing} = nothing
        end
    end
end

Base.show(io::IO, ::MIME"text/plain", err::ValidationError) = print_error(io, err)
function print_error(io, err)
    printstyled(io, typeof(err), color=Base.error_color())
    printstyled(io, "\n      message: ", err.message, color=Base.error_color())
    if !isnothing(err.locations) && !isempty(err.locations)
        if length(err.locations) == 1
            printstyled(io, "\n     location: $(err.locations[1])", color=Base.error_color())
        else
            printstyled(io, "\n  location(s): $(err.locations[1])", color=Base.error_color())
            for i in 2:length(err.locations)
                printstyled(io, "\n               $(err.locations[i])", color=Base.error_color())
            end
        end
    end
end

struct ValidationException <: Exception
    errors::Vector{ValidationError}
end
function Base.showerror(io::IO, ex::ValidationException)
    printstyled(io, "Validation Failed\n", color=Base.error_color(), bold=true)
    for err in ex.errors
        print(io, "\n")
        print_error(io, err)
        print(io, "\n")
    end
end