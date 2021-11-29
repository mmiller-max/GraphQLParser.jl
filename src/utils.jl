iscapitalletter(b) = UInt(0x0041) <= b <= UInt(0x05A) 
islowercaseletter(b) = UInt(0x0061) <= b <= UInt(0x07A)
isnamestart(b) = iscapitalletter(b) || islowercaseletter(b) || b == UInt('_')
isnamecontinue(b) = isnamestart(b) || isdigit(Char(b))

isunicodechar(b) = iscapitalletter(b) || islowercaseletter(b) || isdigit(Char(b))

isstringcontinue(b) = issourcechar(b) && !islineterminator(b)

iscommentstart(b) = b == UInt('#')
iscommentcontinue(b) = issourcechar(b) && !islineterminator(b)
issourcechar(b) = iswhitespace(b) || islineterminator(b) || UInt(0x0020) <= b <= UInt(0xFFFF)

iswhitespace(b) = b == UInt8('\t') || b == UInt8(' ')
islineterminator(b) = b == UInt8('\n') || b == UInt8('\r')
isunicodeBOM(b) = b == UInt(0xFEFF)
isnoncommentignored(b) = iswhitespace(b) || islineterminator(b) || isunicodeBOM(b) || b == UInt(',')

isexponent(b) = b == UInt('E') || b == UInt('e')

# Approach from JSON3.jl
macro eof()
    esc(quote
        if pos > len
            invalid("Unexpected End of File", buf, pos)
        end
    end)
end

macro skip_ignored()
    esc(quote
        b = getbyte(buf, pos)
        while isnoncommentignored(b) || iscommentstart(b)
            if iscommentstart(b)
                pos += 1
                @eof
                b = getbyte(buf, pos)
                while iscommentcontinue(b)
                    pos += 1
                    @eof
                    b = getbyte(buf, pos)
                end
            else
                pos += 1
                @eof
                b = getbyte(buf, pos)
            end
        end
    end)
end

macro eof_skip_ignored()
    esc(quote
        @eof
        @skip_ignored
    end)
end


function only_ignored_left(buf, pos, len)
    while pos <= len
        b = getbyte(buf, pos)
        if isnoncommentignored(b)
            pos += 1
            continue
        end
        if iscommentstart(b)
            while pos <= len && iscommentcontinue(b)
                b = getbyte(buf, pos)
                pos += 1
            end
            continue
        end
        return false
    end
    return true
end

@noinline function invalid(error_text, buf, pos)
    n_chars = 25
    len = length(buf)
    start_char = pos - n_chars
    end_char = pos + n_chars
    indent = n_chars + 1
    if len - pos < n_chars
        indent = n_chars + 1
        end_char = length(buf)
    end
    if pos <= n_chars
        start_char = 1
        indent = pos
    end

    escaped_str = escape_string(String(@view(buf[start_char:end_char])))
    indent += length(escape_string(String(@view(buf[start_char:indent])))) - length(@view(buf[start_char:indent]))
    
    throw(
        ArgumentError(
            """
            invalid GraphQL string at byte position $pos while parsing
                $error_text
                $escaped_str
                $(lpad("^", indent))
            """
        )
    )
end

function getbyte(buf::AbstractVector{UInt8}, pos)
    @inbounds b = buf[pos]
    return b
end