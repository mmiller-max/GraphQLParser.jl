# This code is mostly copied from JSON3: https://github.com/quinnj/JSON3.jl

struct PointerString <: AbstractString
    ptr::Ptr{UInt8}
    len::Int
end

function Base.hash(s::PointerString, h::UInt)
    h += Base.memhash_seed
    ccall(Base.memhash, UInt, (Ptr{UInt8}, Csize_t, UInt32), s.ptr, s.len, h % UInt32) + h
end

import Base: ==
function ==(x::String, y::PointerString)
    sizeof(x) == y.len && ccall(:memcmp, Cint, (Ptr{UInt8}, Ptr{UInt8}, Csize_t), pointer(x), y.ptr, y.len) == 0
end
==(y::PointerString, x::String) = x == y

Base.codeunit(s::PointerString) = UInt8
Base.ncodeunits(s::PointerString) = s.len
@inline function Base.codeunit(s::PointerString, i::Integer)
    @boundscheck checkbounds(s, i)
    unsafe_load(s.ptr + i - 1)
end
Base.String(x::PointerString) = unsafe_string(x.ptr, x.len)

function reverseescapechar(b)
    b == UInt8('"')  && return UInt8('"')
    b == UInt8('\\') && return UInt8('\\')
    b == UInt8('/')  && return UInt8('/')
    b == UInt8('b')  && return UInt8('\b')
    b == UInt8('f')  && return UInt8('\f')
    b == UInt8('n')  && return UInt8('\n')
    b == UInt8('r')  && return UInt8('\r')
    b == UInt8('t')  && return UInt8('\t')
    return 0x00
end

utf16_is_surrogate(c::UInt16) = (c & 0xf800) == 0xd800
utf16_get_supplementary(lead::UInt16, trail::UInt16) = Char(UInt32(lead-0xd7f7)<<10 + trail)

charvalue(b) = (UInt8('0') <= b <= UInt8('9')) ? b - UInt8('0') :
               (UInt8('a') <= b <= UInt8('f')) ? b - (UInt8('a') - 0x0a) :
               (UInt8('A') <= b <= UInt8('F')) ? b - (UInt8('A') - 0x0a) :
               throw(ArgumentError("JSON invalid unicode hex value"))

@noinline invalid_escape(str) = throw(ArgumentError("encountered invalid escape character in json string: \"$(String(str))\""))
@noinline unescaped_control(b) = throw(ArgumentError("encountered unescaped control character in json: '$(escape_string(Base.string(Char(b))))'"))

function unescape(s)
    n = ncodeunits(s)
    buf = Base.StringVector(n)
    len = 1
    i = 1
    @inbounds begin
        while i <= n
            b = codeunit(s, i)
            if b == UInt8('\\')
                i += 1
                i > n && invalid_escape(s)
                b = codeunit(s, i)
                if b == UInt8('u')
                    c = 0x0000
                    i += 1
                    i > n && invalid_escape(s)
                    b = codeunit(s, i)
                    c = (c << 4) + charvalue(b)
                    i += 1
                    i > n && invalid_escape(s)
                    b = codeunit(s, i)
                    c = (c << 4) + charvalue(b)
                    i += 1
                    i > n && invalid_escape(s)
                    b = codeunit(s, i)
                    c = (c << 4) + charvalue(b)
                    i += 1
                    i > n && invalid_escape(s)
                    b = codeunit(s, i)
                    c = (c << 4) + charvalue(b)
                    if utf16_is_surrogate(c)
                        i += 3
                        i > n && invalid_escape(s)
                        c2 = 0x0000
                        b = codeunit(s, i)
                        c2 = (c2 << 4) + charvalue(b)
                        i += 1
                        i > n && invalid_escape(s)
                        b = codeunit(s, i)
                        c2 = (c2 << 4) + charvalue(b)
                        i += 1
                        i > n && invalid_escape(s)
                        b = codeunit(s, i)
                        c2 = (c2 << 4) + charvalue(b)
                        i += 1
                        i > n && invalid_escape(s)
                        b = codeunit(s, i)
                        c2 = (c2 << 4) + charvalue(b)
                        ch = utf16_get_supplementary(c, c2)
                    else
                        ch = Char(c)
                    end
                    st = codeunits(Base.string(ch))
                    for j = 1:length(st)-1
                        @inbounds buf[len] = st[j]
                        len += 1
                    end
                    b = st[end]
                else
                    b = reverseescapechar(b)
                    b == 0x00 && invalid_escape(s)
                end
            end
            @inbounds buf[len] = b
            len += 1
            i += 1
        end
    end
    resize!(buf, len - 1)
    return String(buf)
end

function unescape_blockstr(s)
    n = ncodeunits(s)
    buf = Base.StringVector(n)
    len = 1
    i = 1
    @inbounds begin
        while i <= n
            b = codeunit(s, i)
            if b == UInt8('\\')
                i + 3 > n && invalid_escape(s)
                if codeunit(s, i+1) == UInt8('"') && codeunit(s, i+2) == UInt8('"') && codeunit(s, i+3) == UInt8('"')
                    b = UInt8('"')
                    buf[len] = b
                    len += 1
                    i += 1
                    buf[len] = b
                    len += 1
                    i += 1
                    # Third " added below
                    i += 1 # skip /
                end
            end
            @inbounds buf[len] = b
            len += 1
            i += 1
        end
    end
    resize!(buf, len - 1)
    return String(buf)
end

"""
    format_block_string(str)

Perform the formatting defined here:
https://spec.graphql.org/October2021/#sec-String-Value.Semantics
"""
function format_block_string(str)
    lines = split(str, r"\r|\n") # split by line terminators
    
    common_indent_set = false
    common_indent = 0
    for (i, line) in enumerate(lines)
        i == 1 && continue
        len = length(line)
        indent = count_leading_whitespace(line)
        if indent < len
            if !common_indent_set || indent < common_indent
                common_indent_set = true
                common_indent = indent
            end
        end
    end

    if common_indent_set
        for (i, line) in enumerate(lines)
            i == 1 && continue
            lines[i] = @view(line[common_indent + 1:end])
        end
    end

    i = 1
    lines_to_remove = Int[]
    while all_whitespace(lines[i]) || isempty(lines[i])
        push!(lines_to_remove, i)
        i += 1
    end
    i = length(lines)
    while all_whitespace(lines[i]) || isempty(lines[i])
        push!(lines_to_remove, i)
        i -= 1
    end
    deleteat!(lines, lines_to_remove)
    formatted = ""
    for (i,line) in enumerate(lines)
        if i != 1
            formatted *= '\n'
        end
        formatted *= line
    end
    return formatted
end

function count_leading_whitespace(str)
    count = 0
    for char in str
        if char == '\t' || char == ' '
            count += 1
        else
            break
        end
    end
    return count
end

function all_whitespace(str)
    for char in str
        if !(char == '\t' || char == ' ')
            return false
        end
    end
    return true
end