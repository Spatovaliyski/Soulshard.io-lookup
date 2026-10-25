local _, A = ...
-- Format-2 binary primitives shared by the saved-data writer and reader.
-- Lua 5.1 arithmetic only: no string.pack, bit library or 5.3 operators.
local byte, char, sub, floor, concat = string.byte, string.char, string.sub, math.floor, table.concat
local unpackValues = unpack or table.unpack
local C = {}
A.Codec = C

-- Data files call these while WoW loads them. Registration stores packed strings
-- and small metadata only; nothing is decoded until the dataset is validated.
A.packedBlocks, A.packedFiles = {}, {}

function A.PackedBlock(dataset, kind, realm, first, count, bytes, offsets, payload)
    local blocks = A.packedBlocks
    blocks[#blocks + 1] = { dataset = dataset, kind = kind, realm = realm, first = first, count = count, bytes = bytes, offsets = offsets, payload = payload }
end

function A.PackedFile(dataset, name, blocks)
    local files = A.packedFiles
    files[#files + 1] = { dataset = dataset, name = name, blocks = blocks }
end

local values = {}
local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
for index = 1, 64 do values[byte(alphabet, index)] = index - 1 end
local buffer = {}

-- Decodes characters first..last of a canonical, padded Base64 string.
function C.Base64(text, first, last)
    first, last = first or 1, last or #text
    if first % 4 ~= 1 or (last - first + 1) % 4 ~= 0 or last > #text then error("Invalid Base64 range.") end
    local pieces, count = {}, 0
    for index = first, last, 4 do
        local a, b, c, d = byte(text, index, index + 3)
        a, b = values[a], values[b]
        if not a or not b then error("Invalid Base64.") end
        count = count + 1
        buffer[count] = a * 4 + floor(b / 16)
        if d == 61 then
            if index + 3 ~= #text then error("Invalid Base64 padding.") end
            if c == 61 then
                if b % 16 ~= 0 then error("Non-canonical Base64.") end
            else
                c = values[c]
                if not c or c % 4 ~= 0 then error("Non-canonical Base64.") end
                count = count + 1
                buffer[count] = (b % 16) * 16 + floor(c / 4)
            end
        else
            c, d = values[c], values[d]
            if not c or not d then error("Invalid Base64.") end
            buffer[count + 1] = (b % 16) * 16 + floor(c / 4)
            buffer[count + 2] = (c % 4) * 64 + d
            count = count + 2
        end
        if count >= 3000 then
            pieces[#pieces + 1] = char(unpackValues(buffer, 1, count))
            count = 0
        end
    end
    if count > 0 then pieces[#pieces + 1] = char(unpackValues(buffer, 1, count)) end
    return concat(pieces)
end

-- Returns decoded bytes [start, finish) by decoding only the covering quartets.
function C.Range(text, start, finish)
    if finish <= start then return "" end
    local quartet = floor(start / 3)
    local decoded = C.Base64(text, quartet * 4 + 1, floor((finish + 2) / 3) * 4)
    local skip = start - quartet * 3
    if #decoded < skip + finish - start then error("Truncated Base64 payload.") end
    return sub(decoded, skip + 1, skip + finish - start)
end

-- Reads the zero-based little-endian 32-bit offset from a decoded offset table.
function C.Offset(table, index)
    local a, b, c, d = byte(table, index * 4 + 1, index * 4 + 4)
    if not d then error("Truncated offset table.") end
    return a + b * 256 + c * 65536 + d * 16777216
end

-- Readers take a string, a position and the last readable byte, and return the
-- value followed by the next position.
function C.U8(s, i, j)
    if i > j then error("Truncated value.") end
    return byte(s, i), i + 1
end

function C.Uint(s, i, j)
    local value, scale = 0, 1
    for index = 1, 5 do
        if i > j then error("Truncated value.") end
        local b = byte(s, i)
        i = i + 1
        if index == 5 and b > 15 then error("Unsigned integer overflow.") end
        if b < 128 then
            if b == 0 and index > 1 then error("Overlong unsigned integer.") end
            -- Values from 2^31 use float arithmetic so 32-bit integer test VMs cannot overflow.
            if index == 5 and b >= 8 then return value + b * 268435456.0, i end
            return value + b * scale, i
        end
        value = value + (b - 128) * scale
        scale = scale * 128
    end
end

function C.Bool(s, i, j)
    local value
    value, i = C.U8(s, i, j)
    if value > 1 then error("Invalid boolean.") end
    return value == 1, i
end

function C.Str(s, i, j)
    local length
    length, i = C.Uint(s, i, j)
    if length > 8192 or i + length - 1 > j then error("Invalid string.") end
    return sub(s, i, i + length - 1), i + length
end

function C.Present(s, i, j)
    local marker
    marker, i = C.U8(s, i, j)
    if marker > 1 then error("Invalid presence marker.") end
    return marker == 1, i
end

function C.OptUint(s, i, j)
    local present
    present, i = C.Present(s, i, j)
    if not present then return nil, i end
    return C.Uint(s, i, j)
end

function C.OptStr(s, i, j)
    local present
    present, i = C.Present(s, i, j)
    if not present then return nil, i end
    return C.Str(s, i, j)
end

-- Percentiles are canonical decimal text, so no IEEE-754 decoding is needed.
function C.Parse(s, i, j)
    local text
    text, i = C.Str(s, i, j)
    local value = text:match("^%d+%.?%d*e?%-?%d*$") and tonumber(text)
    if not value or value ~= value or value < 0 or value > 100 then error("Invalid percentile.") end
    return value, i
end

function C.Percentile(s, i, j)
    local present
    present, i = C.Present(s, i, j)
    if not present then return nil, i end
    return C.Parse(s, i, j)
end

local powers = {}
for index = 0, 15 do powers[index] = 2 ^ index end

-- Three bits per rank, least-significant first; 6 and 7 are reserved.
function C.Ranks(s, i, j, count)
    local length = floor((count * 3 + 7) / 8)
    local last = i + length - 1
    if last > j then error("Truncated talent ranks.") end
    local ranks = {}
    for index = 0, count - 1 do
        local bit = index * 3
        local at = i + floor(bit / 8)
        local pair = byte(s, at) + (at < last and byte(s, at + 1) * 256 or 0)
        local rank = floor(pair / powers[bit % 8]) % 8
        if rank > 5 then error("Reserved talent rank.") end
        ranks[index + 1] = rank
    end
    if length > 0 and floor(byte(s, last) / powers[count * 3 - (length - 1) * 8]) ~= 0 then error("Nonzero talent rank padding.") end
    return ranks, last + 1
end
