# This approach heavily borrows from JSON3, with some changes
# for GraphQL specifics and other simplifications

# Each read_{type} function returns pos at the position just after
# it has finished reading

function read(str::AbstractString)
    buf = codeunits(str)
    len = length(buf)

    pos = 1
    @eof 
    @skip_ignored

    definitions, pos = read_definitions(buf, pos, len)
    return Document(definitions)
end

function read_definitions(buf, pos, len)
    b = getbyte(buf, pos)
    @skip_ignored
    
    definitions = Definition[]

    # Check for shorthand
    if b == UInt8('{')
        operation, pos = read_operation(buf, pos, len)
        push!(definitions, operation)
        if pos <= len
            !only_ignored_left(buf, pos, len) && invalid("Shorthand operation only allowed when documet contains only one operation", buf, pos)
        end
        return definitions, pos
    elseif !isnamestart(b)
        invalid("Expected name start character at start of definition", buf, pos)
    else
        while pos <= len
            # operation type
            definition_type, _ = read_name(buf, pos, len)
            definition_type ∉ ("query", "mutation", "subscription", "fragment") && invalid("Definition type can't be $definition_type", buf, pos)
            if definition_type == "fragment"
                fragment, pos = read_fragment_definition(buf, pos, len)
                push!(definitions, fragment)
            else
                operation, pos = read_operation(buf, pos, len)
                push!(definitions, operation)
            end
            only_ignored_left(buf, pos, len) && return definitions, pos
            @skip_ignored
        end
    end
    return definitions, pos
end

function read_operation(buf, pos, len)
    b = getbyte(buf, pos)
    @skip_ignored
    if b == UInt8('{')
        operation_type = "query"
    elseif !isnamestart(b)
        invalid("Expected name start character", buf, pos)
    else
        # operation type
        operation_type, pos = read_name(buf, pos, len)
        operation_type ∉ ("query", "mutation", "subscription") && throw(ArgumentError("operation type can't be $operation_type"))
    end

    @skip_ignored
    b = getbyte(buf, pos)

    if isnamestart(b)
        # name (optional)
        name, pos = read_name(buf, pos, len)
    else
        name = nothing
    end

    @skip_ignored
    b = getbyte(buf, pos)

    if b == UInt('(')
        variables, pos = read_variable_definitions(buf, pos, len)
    else
        variables = nothing
    end

    selection_set, pos = read_selection_set(buf, pos, len)
    return Operation(operation_type, name, variables, nothing, selection_set), pos

end

function read_fragment_definition(buf, pos, len)
    definition_type, pos = read_name(buf, pos, len)
    definition_type != "fragment" && invalid("Fragment definition must start with 'fragment'", buf, pos)
    @eof
    @skip_ignored
    name, pos = read_name(buf, pos, len)
    @eof
    @skip_ignored
    on, pos = read_name(buf, pos, len)
    on != "on" && invalid("Fragment definition must have form 'FragmentName on NamedTime'", buf, pos)
    @eof
    @skip_ignored
    named_type, pos = read_name(buf, pos, len)
    @eof
    @skip_ignored
    b = getbyte(buf, pos) # technically included in skip_ignored?
    if b == UInt('@')
        directives, pos = read_directives(buf, pos, len)
    else
        directives = nothing
    end
    @eof
    @skip_ignored
    selection_set, pos = read_selection_set(buf, pos, len)
    return FragmentDefinition(name, named_type, directives, selection_set), pos
end

function read_variable_definitions(buf, pos, len)
    b = getbyte(buf, pos)
    if b != UInt('(') # redundant check?
        invalid("Variable definitions must start with '('", buf, pos)
    end

    pos += 1
    @eof
    @skip_ignored
    b = getbyte(buf, pos) # is this done in @skip_ignored?

    variables_defs = VariableDefinition[]
    while b != UInt(')')
        if b != UInt('$')
            invalid("Variable name must start with '\$'", buf, pos)
        end

        pos += 1
        @eof
        @skip_ignored

        name, pos = read_name(buf, pos, len)

        @eof
        @skip_ignored
        b = getbyte(buf, pos)

        if b != UInt(':')
            invalid("Variable name and type must be separated by ':'", buf, pos)
        end

        pos += 1  # Move past :
        @eof
        @skip_ignored

        type, pos = read_type(buf, pos, len)

        @eof
        @skip_ignored
        b = getbyte(buf, pos)

        # default value
        if b == UInt('=')
            pos += 1
            @eof
            @skip_ignored
            value, pos = read_value(buf, pos, len)
        else
            value = nothing
        end

        # directives
        if b == UInt('@')
            pos += 1
            @eof
            @skip_ignored
            directive, pos = read_directives(buf, pos, len)
        else
            directive = nothing
        end

        push!(variables_defs, VariableDefinition(name, type, value, directive))
        @eof
        @skip_ignored
        b = getbyte(buf, pos)
    end
    pos += 1 # move past )
    return variables_defs, pos
@label invalid
    invalid(error_text, buf, pos)
end

function read_directives(buf, pos, len)
    directives = Directive[]
    while pos <= len && getbyte(buf, pos) == UInt('@')
        directive, pos = read_directive(buf, pos, len)
        push!(directives, directive)
    end
    return directives, pos
end

function read_directive(buf, pos, len)
    b = getbyte(buf, pos)
    if b != UInt('@') # redundant check?
        invalid("Directives must start with '@'", buf, pos)
    end

    pos += 1
    @eof
    @skip_ignored

    name, pos = read_name(buf, pos, len)

    if pos > len
        return Directive(name, nothing), pos
    end

    @skip_ignored
    if b == UInt('(')
        arguments, pos = read_arguments(buf, pos, len)
    end

    return Directive(name, arguments), pos

end

function read_type(buf, pos, len)
    type_str = ""
    b = getbyte(buf, pos)
    if b == UInt('[')
        type_str *= "["
        pos += 1
        @eof
        @skip_ignored
        name, pos = read_type(buf, pos, len)
        type_str *= name
        @eof
        @skip_ignored
        b = getbyte(buf, pos)
        if b == UInt('!')
            type_str *= "!"
            pos += 1
            @eof
            @skip_ignored
        end
        b = getbyte(buf, pos)
        if b != UInt(']')
            invalid("Expected ']' in type", buf, pos)
        end
        type_str *= "]"
        pos += 1
    else
        name, pos = read_name(buf, pos, len)
        type_str *= name
    end
    if pos > len
        return type_str, pos
    end
    b = getbyte(buf, pos)
    if b == UInt('!')
        type_str *= "!"
        pos += 1
    end
    return type_str, pos
end

function read_name(buf, pos, len)
    b = getbyte(buf, pos)
    @skip_ignored

    if !isnamestart(b)
        invalid("Expected name start character", buf, pos)
    end

    startpos = pos
    namelen = 0
    while isnamecontinue(b) && pos <= len
        pos += 1
        namelen += 1
        if pos <= len
            b = getbyte(buf, pos)
        end
    end
    name = unsafe_string(pointer(buf, startpos), namelen)
    return name, pos
end

function read_selection_set(buf, pos, len)
    b = getbyte(buf, pos)
    @skip_ignored
    if b !== UInt8('{')
        invalid("Expected '{'", buf, pos)
    end

    pos += 1
    @eof
    @skip_ignored
    b = getbyte(buf, pos)

    selections = Selection[]
    while b !== UInt8('}')
        selection, pos = read_selection(buf, pos, len)
        push!(selections, selection)
        @eof
        b = getbyte(buf, pos)
        @skip_ignored
    end
    pos += 1 # Move past '}'

    return SelectionSet(selections), pos
end

function read_selection(buf, pos, len)
    b = getbyte(buf, pos)
    if b == UInt('.') && getbyte(buf, pos+1) == UInt('.') && getbyte(buf, pos+2) == UInt('.')
        return read_fragment(buf, pos, len)
    else
        # Field
        return read_field(buf, pos, len)
    end
end

function read_fragment(buf, pos, len)
    b = getbyte(buf, pos)
    if !(b == UInt('.') && getbyte(buf, pos+1) == UInt('.') && getbyte(buf, pos+2) == UInt('.'))
        # Are these and similar conditions necessary if we're already checking further up?
        invalid("Inline fragments and fragment spread must start '...", buf, pos)
    end
    pos += 3
    @eof
    @skip_ignored
    b = getbyte(buf, pos)
    if isnamestart(b)
        name, pos = read_name(buf, pos, len)
        if name !== "on"
            @eof
            @skip_ignored
            b = getbyte(buf, pos)
            if b == UInt('@')
                directives, pos = read_directives(buf, pos, len)
            else
                directives = nothing
            end
            return FragmentSpread(name, directives), pos
        end

        # Inline fragment starting with type condition
        @eof
        @skip_ignored
        named_type, pos = read_name(buf, pos, len)
    else
        named_type = nothing
    end

    # Only get here with inline fragment
    if b == UInt('@')
        directives, pos = read_directives(buf, pos, len)
    else
        directives = nothing
    end

    @eof
    @skip_ignored
    b = getbyte(buf, pos)

    selection_set, pos = read_selection_set(buf, pos, len)
    return InlineFragment(named_type, directives, selection_set), pos
end

function read_number(buf, pos, len)
    b = getbyte(buf, pos)

    number_start = pos
    number_length = 0

    if b == UInt('-')
        pos += 1
        number_length += 1
        @eof
        b = getbyte(buf, pos)
    end

    if b == UInt('0')
        if pos + 1 < len && isdigit(Char(getbyte(buf, pos+1)))
            error("IntValue or FloatValue cannot begin with leading zero")
        end
    end

    while isdigit(Char(b))
        number_length += 1
        pos += 1
        if pos > len
            # Need this check when single digit is at end of buffer
            @inbounds @views value = Parsers.parse(Int64, buf[number_start:number_start+number_length-1])
            return value, pos
        end
        b = getbyte(buf, pos)
    end

    if !(b == UInt('.') || isexponent(b))
        if islowercaseletter(b) || iscapitalletter(b)
            error("Integer value cannot be followed by a name char") # Refine
        end
        @inbounds @views value = Parsers.parse(Int64, buf[number_start:number_start+number_length-1])
    else
        while isdigit(Char(b)) || b == UInt('.') || isexponent(b) || b == UInt('+') || b == UInt('-')
            # Could do better checking here
            number_length += 1
            pos += 1
            if pos > len
                # shouldn't get here but useful for testing function
                break
            end
            b = getbyte(buf, pos)
        end
        @inbounds @views value = Parsers.parse(Float64, buf[number_start:number_start+number_length-1])
    end
    return value, pos
end

function read_string(buf, pos, len)
    b = getbyte(buf, pos)
    escaped = false
    if b == UInt('"') && getbyte(buf, pos+1) == UInt('"') && getbyte(buf, pos+2) == UInt('"')
        isblockstr = true
        pos += 3
        @eof
        b = getbyte(buf, pos)
        stringlen = 0
        stringstart = pos

        while !(b == UInt('"') && getbyte(buf, pos+1) == UInt('"') && getbyte(buf, pos+2) == UInt('"'))
            if b == UInt('\\') && all((i) -> getbyte(buf, pos+i) == UInt('"'), (1,2,3))
                # Escaped block string
                escaped = true
                pos += 4
                stringlen += 4
            else
                pos += 1
                stringlen += 1
            end
            @eof
            b = getbyte(buf, pos)
        end
        # Get past remaining """
        pos += 3
    else
        isblockstr = false
        pos += 1
        @eof
        b = getbyte(buf, pos)
        stringlen = 0
        stringstart = pos
        while b != UInt('"')
            if b == UInt('\\')
                escaped = true
                if getbyte(buf, pos+1) == UInt('u')
                    # unicode
                    if !all((i) -> isunicodechar(getbyte(buf, pos+i)), (2,3,4,5))
                        invalid("Unicode must have four digits", buf, pos)
                    end
                    pos += 5
                    stringlen += 5
                else
                    # other escaped characted
                    pos += 2
                    stringlen += 2
                end
            else
                pos += 1
                stringlen += 1
            end
            @eof
            b = getbyte(buf, pos)
        end

        # Get past remaining "
        pos += 1
    end
    if escaped
        if isblockstr
            return format_block_string(unescape_blockstr(PointerString(pointer(buf, stringstart), stringlen))), pos
        else
            return unescape(PointerString(pointer(buf, stringstart), stringlen)), pos
        end
    else
        if isblockstr
            return format_block_string(unsafe_string(pointer(buf, stringstart), stringlen)), pos
        else
            return unsafe_string(pointer(buf, stringstart), stringlen), pos
        end
    end
end

function read_arguments(buf, pos, len)
    b = getbyte(buf, pos)
    if b != UInt('(')
        invalid("Arguments must start with (", buf, pos)
    end

    pos +=1 
    @eof
    b = getbyte(buf, pos)
    @skip_ignored

    arguments = Argument[]

    while b!= UInt(')')
        argument, pos = read_argument(buf, pos, len)
        push!(arguments, argument)
        @eof
        @skip_ignored
    end

    isempty(arguments) && invalid("Expected at least one argument", buf, pos)
    # Move past )
    pos +=1 

    return arguments, pos
end
function read_argument(buf, pos, len)
    # Get name (either name)
    name, pos = read_name(buf, pos, len)
    b = getbyte(buf, pos)
    @skip_ignored

    # Check :
    if b != UInt(':')
        invalid("Expected : in argument", buf, pos)
    end
    pos += 1
    @eof
    b = getbyte(buf, pos)
    @skip_ignored

    # Get value
    value, pos = read_value(buf, pos, len)

    return Argument(name, value), pos
end

function read_value(buf, pos, len)
    b = getbyte(buf, pos)
    if isdigit(Char(b)) || b == UInt('-')
        value, pos = read_number(buf, pos, len)
    elseif b == UInt('t') && getbyte(buf, pos+1) == UInt('r') && getbyte(buf, pos+2) == UInt('u') && getbyte(buf, pos+3) == UInt('e')
        # will fail if shorter than this
        value = true
        pos += 4
    elseif b == UInt('f') && getbyte(buf, pos+1) == UInt('a') && getbyte(buf, pos+2) == UInt('l') && getbyte(buf, pos+3) == UInt('s') && getbyte(buf, pos+4) == UInt('e')
        value = false
        pos += 5
    elseif b == UInt('n') && getbyte(buf, pos+1) == UInt('u') && getbyte(buf, pos+2) == UInt('l') && getbyte(buf, pos+3) == UInt('l')
        value = nothing
        pos += 4
    elseif b == UInt('"')
        value, pos = read_string(buf, pos, len)
        @eof # needed as not checked in read_string
    elseif b == UInt('[')
        value, pos = read_list(buf, pos, len)
    elseif b == UInt('{')
        # Input object
        value, pos = read_input_object(buf, pos, len)
    elseif isnamestart(b)
        # enum
        value_str, pos = read_name(buf, pos, len)
        value = Enum(value_str)
    elseif b == UInt('$')
        # variable
        pos += 1
        @eof
        @skip_ignored
        name, pos = read_name(buf, pos, len)
        value = Variable(name)
    else
        invalid("Could not parse value", buf, pos)
    end

    return value, pos
end

function read_input_object(buf, pos, len)
    b = getbyte(buf, pos)
    if b != UInt('{')
        invalid("Input object must start with {", buf, pos)
    end

    pos += 1
    @eof
    @skip_ignored

    object_fields = ObjectField[]

    while b != UInt('}')
        if !isnamestart(b)
            invalid("Expected name start character or '}'", buf, pos)
        end

        name, pos = read_name(buf, pos, len)

        @eof
        @skip_ignored

        if b != UInt(':')
            invalid("ObjectField name must be followed by ':'", buf, pos)
        end

        pos += 1
        @eof
        b = getbyte(buf, pos)
        @skip_ignored

        value, pos = read_value(buf, pos, len)
        push!(object_fields, ObjectField(name, value))
        @eof
        @skip_ignored
        b = getbyte(buf, pos)
    end

    # Move past }
    pos += 1

    return InputObject(object_fields), pos
end

function read_list(buf, pos, len)
    b = getbyte(buf, pos)
    if b != UInt('[')
        invalid("List must start with [", buf, pos)
    end

    pos += 1
    @eof
    @skip_ignored
    b = getbyte(buf, pos)

    list = Any[] # TODO: we'd use introspection here to determine the type of the list.
    
    first_element = true
    while b != UInt(']')
        value, pos = read_value(buf, pos, len)
        push!(list, value)
        !first_element && @assert typeof(value) == typeof(first(list))
        @eof
        @skip_ignored
    end

    # Move past ]
    pos += 1

    return list, pos
end

function read_field(buf, pos, len)
    # Get first name (either name or alias)
    name, pos = read_name(buf, pos, len)
    alias::Union{String, Nothing} = nothing
    if pos > len
        # Shouldn't really happen but useful for tests
        field = Field(alias, name, nothing, nothing, nothing)
        return field, pos
    end
    b = getbyte(buf, pos)
    @skip_ignored

    # Check for alias
    if b == UInt(':')
        # Alias
        pos += 1
        @eof
        b = getbyte(buf, pos)
        @skip_ignored
        alias = name
        name, pos = read_name(buf, pos, len)
    end
    if pos > len
        # Shouldn't really happen but useful for tests
        field = Field(alias, name, nothing, nothing, nothing)
        return field, pos
    end
    b = getbyte(buf, pos)
    @skip_ignored

    # Check for arguments
    if b == UInt8('(')
        arguments, pos = read_arguments(buf, pos, len)
    else
        arguments = nothing
    end
    b = getbyte(buf, pos)
    @skip_ignored

    # Check for directives
    if b == UInt('@')
        directives = read_directives(buf, pos, len)
    else
        directives = nothing
    end

    # Check for selection set
    if b == UInt8('{')
        # SelectionSet
        selection_set, pos = read_selection_set(buf, pos, len)
    else
        selection_set = nothing
    end

    # Build operation from tape
    field = Field(alias, name, arguments, directives, selection_set)
    return field, pos
end