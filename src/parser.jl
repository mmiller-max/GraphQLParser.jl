# This approach heavily borrows from JSON3, with some changes
# for GraphQL specifics and other simplifications

# Each parse_{type} function
# - assumes that pos is the first character of what it is trying to parse (i.e. not an ignored charactaer)
# - returns pos at the position just after it has finished reading

"""
    parse(str::AbstractString)

Parses a GraphQL executable document string.
"""
function parse(str::AbstractString)
    buf = codeunits(str)
    len = length(buf)

    pos = 1
    line = 1
    column = 1
    @eof 
    @skip_ignored

    definitions, pos, line, column = parse_definitions(buf, pos, line, column, len)
    return Document(definitions)
end

function parse_definitions(buf, pos, line, column, len)
    b = getbyte(buf, pos)
    definitions = Definition[]

    # Check for shorthand
    while pos <= len
        if b == UInt8('{')
            operation, pos, line, column = parse_operation(buf, pos, line, column, len)
            push!(definitions, operation)
        elseif !isnamestart(b)
            invalid("Expected name start character at start of definition", buf, pos)
        else
            # operation type
            definition_type, _, _, _ = parse_name(buf, pos, line, column, len)
            definition_type ∉ ("query", "mutation", "subscription", "fragment") && invalid("Definition type can't be \"$definition_type\"", buf, pos)
            if definition_type == "fragment"
                fragment, pos, line, column = parse_fragment_definition(buf, pos, line, column, len)
                push!(definitions, fragment)
            else
                operation, pos, line, column = parse_operation(buf, pos, line, column, len)
                push!(definitions, operation)
            end
        end
        only_ignored_left(buf, pos, len) && return definitions, pos, line, column
        @skip_ignored
    end
    return definitions, pos, line, column
end

function parse_operation(buf, pos, line, column, len)
    start_line = line
    start_column = column
    b = getbyte(buf, pos)
    if b == UInt8('{')
        operation_type = "query"
    elseif !isnamestart(b)
        invalid("Expected name start character", buf, pos)
    else
        # operation type
        operation_type, pos, line, column = parse_name(buf, pos, line, column, len)
        operation_type ∉ ("query", "mutation", "subscription") && throw(ArgumentError("operation type can't be $operation_type"))
    end

    @eof_skip_ignored

    if isnamestart(b)
        # name (optional)
        name, pos, line, column = parse_name(buf, pos, line, column, len)
    else
        name = nothing
    end

    @eof_skip_ignored

    if b == UInt('(')
        variables, pos, line, column = parse_variable_definitions(buf, pos, line, column, len)
    else
        variables = nothing
    end

    @eof_skip_ignored

    selection_set, pos, line, column = parse_selection_set(buf, pos, line, column, len)
    operation = Operation(operation_type, name, variables, nothing, selection_set, Loc(start_line, start_column))
    return operation, pos, line, column
end

function parse_fragment_definition(buf, pos, line, column, len)
    start_line = line
    start_column = column
    definition_type, pos, line, column = parse_name(buf, pos, line, column, len)
    definition_type != "fragment" && invalid("Fragment definition must start with 'fragment'", buf, pos)
    @eof_skip_ignored
    first_name_pos = pos
    name, pos, line, column = parse_name(buf, pos, line, column, len)
    @eof_skip_ignored
    on, pos, line, column = parse_name(buf, pos, line, column, len)
    on != "on" && invalid("Fragment definition must have form 'FragmentName on NamedTime'", buf, first_name_pos)
    @eof_skip_ignored
    named_type, pos, line, column = parse_name(buf, pos, line, column, len)
    @eof_skip_ignored
    if b == UInt('@')
        directives, pos, line, column = parse_directives(buf, pos, line, column, len)
    else
        directives = nothing
    end
    @eof_skip_ignored
    selection_set, pos, line, column = parse_selection_set(buf, pos, line, column, len)
    fragment_definition = FragmentDefinition(name, named_type, directives, selection_set, Loc(start_line, start_column))
    return fragment_definition, pos, line, column
end

function parse_variable_definitions(buf, pos, line, column, len)
    start_line = line
    start_column = column
    b = getbyte(buf, pos)
    if b != UInt('(') # redundant check?
        invalid("Variable definitions must start with '('", buf, pos)
    end

    pos += 1
    column += 1
    @eof_skip_ignored

    variables_defs = VariableDefinition[]
    while b != UInt(')')
        if b != UInt('$')
            invalid("Variable name must start with '\$'", buf, pos)
        end

        pos += 1
        column += 1
        @eof_skip_ignored

        name, pos, line, column = parse_name(buf, pos, line, column, len)

        @eof_skip_ignored

        if b != UInt(':')
            invalid("Variable name and type must be separated by ':'", buf, pos)
        end

        pos += 1  # Move past ':'
        column += 1
        @eof_skip_ignored

        type, pos, line, column = parse_type(buf, pos, line, column, len)

        @eof_skip_ignored

        # default value
        if b == UInt('=')
            pos += 1
            column += 1
            @eof_skip_ignored
            value, pos, line, column = parse_value(buf, pos, line, column, len)
        else
            value = nothing
        end

        # directives
        if b == UInt('@')
            pos += 1
            column += 1
            @eof_skip_ignored
            directive, pos, line, column = parse_directives(buf, pos, line, column, len)
        else
            directive = nothing
        end

        push!(variables_defs, VariableDefinition(name, type, value, directive, Loc(start_line, start_column)))
        @eof_skip_ignored
        b = getbyte(buf, pos)
    end
    pos += 1 # move past )
    column += 1
    return variables_defs, pos, line, column
end

function parse_directives(buf, pos, line, column, len)
    directives = Directive[]
    while pos <= len && getbyte(buf, pos) == UInt('@')
        directive, pos, line, column = parse_directive(buf, pos, line, column, len)
        push!(directives, directive)
        @eof_skip_ignored
    end
    return directives, pos, line, column
end

function parse_directive(buf, pos, line, column, len)
    start_line = line
    start_column = column
    b = getbyte(buf, pos)
    if b != UInt('@') # redundant check?
        invalid("Directives must start with '@'", buf, pos)
    end

    pos += 1
    column += 1
    @eof_skip_ignored

    name, pos, line, column = parse_name(buf, pos, line, column, len)

    if pos > len
        return Directive(name, nothing, Loc(start_line, start_column)), pos, line, column
    end

    @skip_ignored
    if b == UInt('(')
        arguments, pos, line, column = parse_arguments(buf, pos, line, column, len)
    end

    return Directive(name, arguments, Loc(start_line, start_column)), pos, line, column
end

function parse_type(buf, pos, line, column, len)
    type_str = ""
    b = getbyte(buf, pos)
    if b == UInt('[')
        type_str *= "["
        pos += 1
        column += 1
        @eof_skip_ignored
        name, pos, line, column = parse_type(buf, pos, line, column, len)
        type_str *= name
        @eof_skip_ignored
        b = getbyte(buf, pos)
        if b == UInt('!')
            type_str *= "!"
            pos += 1
            column += 1
            @eof_skip_ignored
        end
        b = getbyte(buf, pos)
        if b != UInt(']')
            invalid("Expected ']' in type", buf, pos)
        end
        type_str *= "]"
        pos += 1
        column += 1
    else
        name, pos, line, column = parse_name(buf, pos, line, column, len)
        type_str *= name
    end
    if pos > len
        return type_str, pos, line, column
    end
    b = getbyte(buf, pos)
    if b == UInt('!')
        type_str *= "!"
        pos += 1
        column += 1
    end
    return type_str, pos, line, column
end

function parse_name(buf, pos, line, column, len)
    b = getbyte(buf, pos)
    if !isnamestart(b)
        invalid("Expected name start character", buf, pos)
    end

    startpos = pos
    namelen = 0
    while isnamecontinue(b) && pos <= len
        pos += 1
        column += 1
        namelen += 1
        if pos <= len
            b = getbyte(buf, pos)
        end
    end
    name = unsafe_string(pointer(buf, startpos), namelen)
    return name, pos, line, column
end

function parse_selection_set(buf, pos, line, column, len)
    start_line = line
    start_column = column
    b = getbyte(buf, pos)
    @skip_ignored
    if b !== UInt8('{')
        invalid("Expected '{'", buf, pos)
    end

    pos += 1
    column += 1
    @eof_skip_ignored

    selections = Selection[]
    while b !== UInt8('}')
        selection, pos, line, column = parse_selection(buf, pos, line, column, len)
        push!(selections, selection)
        @eof
        @skip_ignored
    end
    pos += 1 # Move past '}'
    column += 1

    return SelectionSet(selections, Loc(start_line, start_column)), pos, line, column
end

function parse_selection(buf, pos, line, column, len)
    b = getbyte(buf, pos)
    if b == UInt('.') && getbyte(buf, pos+1) == UInt('.') && getbyte(buf, pos+2) == UInt('.')
        return parse_fragment(buf, pos, line, column, len)
    else
        # Field
        return parse_field(buf, pos, line, column, len)
    end
end

function parse_fragment(buf, pos, line, column, len)
    b = getbyte(buf, pos)
    if !(b == UInt('.') && getbyte(buf, pos+1) == UInt('.') && getbyte(buf, pos+2) == UInt('.'))
        # Are these and similar conditions necessary if we're already checking further up?
        invalid("Inline fragments and fragment spread must start '...", buf, pos)
    end
    pos += 3
    column += 3
    start_line = line
    start_column = column
    @eof_skip_ignored
    b = getbyte(buf, pos)
    if isnamestart(b)
        name, pos, line, column = parse_name(buf, pos, line, column, len)
        if name !== "on"
            @eof_skip_ignored
            b = getbyte(buf, pos)
            if b == UInt('@')
                directives, pos, line, column = parse_directives(buf, pos, line, column, len)
            else
                directives = nothing
            end
            @eof_skip_ignored
            b = getbyte(buf, pos)
            return FragmentSpread(name, directives, Loc(start_line, start_column)), pos, line, column
        end

        # Inline fragment starting with type condition
        @eof_skip_ignored
        named_type, pos, line, column = parse_name(buf, pos, line, column, len)
        @eof_skip_ignored
    else
        named_type = nothing
    end

    # Only get here with inline fragment
    if b == UInt('@')
        directives, pos, line, column = parse_directives(buf, pos, line, column, len)
    else
        directives = nothing
    end

    @eof_skip_ignored

    selection_set, pos, line, column = parse_selection_set(buf, pos, line, column, len)
    return InlineFragment(named_type, directives, selection_set, Loc(start_line, start_column)), pos, line, column
end

function parse_number(buf, pos, line, column, len)
    b = getbyte(buf, pos)

    number_start = pos
    number_length = 0

    if b == UInt('-')
        pos += 1
        column += 1
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
        column += 1
        if pos > len
            # Need this check when single digit is at end of buffer
            @inbounds @views value = Parsers.parse(Int64, buf[number_start:number_start+number_length-1])
            return value, pos, line, column
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
            column += 1
            if pos > len
                # shouldn't get here but useful for testing function
                break
            end
            b = getbyte(buf, pos)
        end
        @inbounds @views value = Parsers.parse(Float64, buf[number_start:number_start+number_length-1])
    end
    return value, pos, line, column
end

function parse_string(buf, pos, line, column, len)
    b = getbyte(buf, pos)
    escaped = false
    if b == UInt('"') && getbyte(buf, pos+1) == UInt('"') && getbyte(buf, pos+2) == UInt('"')
        isblockstr = true
        pos += 3
        column += 3
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
                column += 4
            else
                if islineterminator(b)
                    line += 1
                    column = 1
                else
                    column += 1
                end
                pos += 1
                stringlen += 1
            end
            @eof
            b = getbyte(buf, pos)
        end
        # Get past remaining """
        pos += 3
        column += 3
    else
        isblockstr = false
        pos += 1
        column += 1
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
                    column += 5
                    stringlen += 5
                else
                    # other escaped characted
                    pos += 2
                    column += 2
                    stringlen += 2
                end
            else
                pos += 1
                column += 1
                stringlen += 1
            end
            @eof
            b = getbyte(buf, pos)
        end

        # Get past remaining "
        pos += 1
        column += 1
    end
    if escaped
        if isblockstr
            return format_block_string(unescape_blockstr(PointerString(pointer(buf, stringstart), stringlen))), pos, line, column
        else
            return unescape(PointerString(pointer(buf, stringstart), stringlen)), pos, line, column
        end
    else
        if isblockstr
            return format_block_string(unsafe_string(pointer(buf, stringstart), stringlen)), pos, line, column
        else
            return unsafe_string(pointer(buf, stringstart), stringlen), pos, line, column
        end
    end
end

function parse_arguments(buf, pos, line, column, len)
    b = getbyte(buf, pos)
    if b != UInt('(')
        invalid("Arguments must start with (", buf, pos)
    end

    pos += 1
    column += 1
    @eof_skip_ignored

    arguments = Argument[]

    while b!= UInt(')')
        argument, pos, line, column = parse_argument(buf, pos, line, column, len)
        push!(arguments, argument)
        @eof_skip_ignored
    end

    isempty(arguments) && invalid("Expected at least one argument", buf, pos)
    # Move past ')'
    pos +=1 
    column += 1

    return arguments, pos, line, column
end
function parse_argument(buf, pos, line, column, len)
    start_line = line
    start_column = column
    # Get name (either name)
    name, pos, line, column = parse_name(buf, pos, line, column, len)
    b = getbyte(buf, pos)
    @skip_ignored

    # Check :
    if b != UInt(':')
        invalid("Expected : in argument", buf, pos)
    end
    pos += 1
    column += 1
    @eof_skip_ignored

    # Get value
    value, pos, line, column = parse_value(buf, pos, line, column, len)

    return Argument(name, value, Loc(start_line, start_column)), pos, line, column
end

function parse_value(buf, pos, line, column, len)
    b = getbyte(buf, pos)
    if isdigit(Char(b)) || b == UInt('-')
        value, pos, line, column = parse_number(buf, pos, line, column, len)
    elseif b == UInt('t') && getbyte(buf, pos+1) == UInt('r') && getbyte(buf, pos+2) == UInt('u') && getbyte(buf, pos+3) == UInt('e')
        # will fail if shorter than this
        value = true
        pos += 4
        column += 4
    elseif b == UInt('f') && getbyte(buf, pos+1) == UInt('a') && getbyte(buf, pos+2) == UInt('l') && getbyte(buf, pos+3) == UInt('s') && getbyte(buf, pos+4) == UInt('e')
        value = false
        pos += 5
        column += 5
    elseif b == UInt('n') && getbyte(buf, pos+1) == UInt('u') && getbyte(buf, pos+2) == UInt('l') && getbyte(buf, pos+3) == UInt('l')
        value = nothing
        pos += 4
        column += 4
    elseif b == UInt('"')
        value, pos, line, column = parse_string(buf, pos, line, column, len)
        @eof # needed as not checked in parse_string
    elseif b == UInt('[')
        value, pos, line, column = parse_list(buf, pos, line, column, len)
    elseif b == UInt('{')
        # Input object
        value, pos, line, column = parse_input_object(buf, pos, line, column, len)
    elseif isnamestart(b)
        # enum
        start_line = line
        start_column = column
        value_str, pos, line, column = parse_name(buf, pos, line, column, len)
        value = Enum(value_str, Loc(start_line, start_column))
    elseif b == UInt('$')
        # variable
        pos += 1
        column += 1
        @eof_skip_ignored
        name, pos, line, column = parse_name(buf, pos, line, column, len)
        value = Variable(name)
    else
        invalid("Could not parse value", buf, pos)
    end

    return value, pos, line, column
end

function parse_input_object(buf, pos, line, column, len)
    start_line = line
    start_column = column
    b = getbyte(buf, pos)
    if b != UInt('{')
        invalid("Input object must start with {", buf, pos)
    end

    pos += 1
    column += 1
    @eof_skip_ignored

    object_fields = ObjectField[]

    while b != UInt('}')
        if !isnamestart(b)
            invalid("Expected name start character or '}'", buf, pos)
        end

        name, pos, line, column = parse_name(buf, pos, line, column, len)

        @eof_skip_ignored

        if b != UInt(':')
            invalid("ObjectField name must be followed by ':'", buf, pos)
        end

        pos += 1
        column += 1
        @eof_skip_ignored

        value, pos, line, column = parse_value(buf, pos, line, column, len)
        push!(object_fields, ObjectField(name, value, Loc(start_line, start_column)))
        @eof_skip_ignored
    end

    # Move past '}'
    pos += 1
    column += 1

    return InputObject(object_fields, Loc(start_line, start_column)), pos, line, column
end

function parse_list(buf, pos, line, column, len)
    b = getbyte(buf, pos)
    if b != UInt('[')
        invalid("List must start with [", buf, pos)
    end

    pos += 1
    column += 1
    @eof_skip_ignored
    b = getbyte(buf, pos)

    list = Any[] # TODO: we'd use introspection here to determine the type of the list.
    
    first_element = true
    while b != UInt(']')
        value, pos, line, column = parse_value(buf, pos, line, column, len)
        push!(list, value)
        !first_element && @assert typeof(value) == typeof(first(list))
        @eof_skip_ignored
    end

    # Move past ']'
    pos += 1
    column += 1

    return list, pos, line, column
end

function parse_field(buf, pos, line, column, len)
    start_line = line
    start_column = column
    # Get first name (either name or alias)
    name, pos, line, column = parse_name(buf, pos, line, column, len)
    alias::Union{String, Nothing} = nothing
    if pos > len
        # Shouldn't really happen but useful for tests
        field = Field(alias, name, nothing, nothing, nothing, Loc(start_line, start_column))
        return field, pos, line, column, len
    end
    b = getbyte(buf, pos)
    @skip_ignored

    # Check for alias
    if b == UInt(':')
        # Alias
        pos += 1
        column += 1
        @eof_skip_ignored
        alias = name
        name, pos, line, column = parse_name(buf, pos, line, column, len)
    end
    if pos > len
        # Shouldn't really happen but useful for tests
        field = Field(alias, name, nothing, nothing, nothing, Loc(start_line, start_column))
        return field, pos
    end
    b = getbyte(buf, pos)
    @skip_ignored

    # Check for arguments
    if b == UInt8('(')
        arguments, pos, line, column = parse_arguments(buf, pos, line, column, len)
    else
        arguments = nothing
    end
    b = getbyte(buf, pos)
    @skip_ignored # TODO: what if arguments and nothing else after?

    # Check for directives
    if b == UInt('@')
        directives, pos, line, column = parse_directives(buf, pos, line, column, len)
    else
        directives = nothing
    end
    b = getbyte(buf, pos)
    @skip_ignored # TODO: what if arguments and nothing else after?

    # Check for selection set
    if b == UInt8('{')
        # SelectionSet
        selection_set, pos, line, column = parse_selection_set(buf, pos, line, column, len)
    else
        selection_set = nothing
    end

    # Build operation from tape
    field = Field(alias, name, arguments, directives, selection_set, Loc(start_line, start_column))
    return field, pos, line, column
end