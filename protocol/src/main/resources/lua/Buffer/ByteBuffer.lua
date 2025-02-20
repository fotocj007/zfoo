--默认为大端模式
--支持的lua版本为>=5.3
--支持标准的Lua是使用64-bit的int以及64-bit的双精度float
--当lua只能支持32位的整数类型时，可以考虑用Long来替代，需要修改原代码
--右移操作>>是无符号右移
--local Long = require("Long")

local maxInt = 2147483647
local minInt = -2147483648
local initSize = 128
local zeroByte = string.char(0)

local ByteBuffer = {}

local trueBooleanStrValue = string.char(1)
local falseBooleanStrValue = string.char(0)

-------------------------------------构造器-------------------------------------
function ByteBuffer:new()
    --buffer里的每一个元素为一个长度为1的字符串
    local obj = {
        buffer = {},
        writeOffset = 1,
        readOffset = 1
    }
    setmetatable(obj, self)
    self.__index = self

    for i = 1, initSize do
        table.insert(obj.buffer, zeroByte)
    end
    return obj
end


-------------------------------------UTF8-------------------------------------
-- 判断utf8字符byte长度
-- 0xxxxxxx - 1 byte
-- 110yxxxx - 192, 2 byte
-- 1110yyyy - 225, 3 byte
-- 11110zzz - 240, 4 byte
local function chsize(char)
    if not char then
        print("not char")
        return 0
    elseif char > 240 then
        return 4
    elseif char > 225 then
        return 3
    elseif char > 192 then
        return 2
    else
        return 1
    end
end


-- 截取utf8 字符串
-- str:            要截取的字符串
-- startChar:    开始字符下标,从1开始
-- numChars:    要截取的字符长度
local function utf8sub(str, startChar, numChars)
    local startIndex = 1
    while startChar > 1 do
        local char = string.byte(str, startIndex)
        startIndex = startIndex + chsize(char)
        startChar = startChar - 1
    end

    local currentIndex = startIndex

    while numChars > 0 and currentIndex <= #str do
        local char = string.byte(str, currentIndex)
        currentIndex = currentIndex + chsize(char)
        numChars = numChars - 1
    end
    return str:sub(startIndex, currentIndex - 1)
end


-------------------------------------get和set-------------------------------------
function ByteBuffer:getWriteOffset()
    return self.writeOffset
end

function ByteBuffer:setWriteOffset(writeOffset)
    if writeOffset > #self.buffer then
        error("index out of bounds exception: readerIndex: " + self.readOffset
                + ", writerIndex: " + self.writeOffset
                + "(expected: 0 <= readerIndex <= writerIndex <= capacity:" + #self.buffer)
    end
    self.writeOffset = writeOffset
    return self
end

function ByteBuffer:getReadOffset()
    return self.readOffset
end

function ByteBuffer:setReadOffset(readOffset)
    if readOffset > self.writeOffset then
        error("index out of bounds exception: readerIndex: " + self.readOffset
                + ", writerIndex: " + this.writeOffset
                + "(expected: 0 <= readerIndex <= writerIndex <= capacity:" + #self.buffer)
    end
    self.readOffset = readOffset
    return self
end

function ByteBuffer:getLen()
    return #self.buffer
end

function ByteBuffer:getAvailable()
    return #self.buffer - self.writeOffset + 1
end

-------------------------------------write和read-------------------------------------

--bool
function ByteBuffer:writeBoolean(boolValue)
    if boolValue then
        self:writeRawByteStr(trueBooleanStrValue)
    else
        self:writeRawByteStr(falseBooleanStrValue)
    end
    return self
end

function ByteBuffer:readBoolean()
    -- When char > 256, the readUByte method will show an error.
    -- So, we have to use readChar
    return self:readRawByteStr() == trueBooleanStrValue
end


--- byte
-- The byte is a number between -128 and 127, otherwise, the lua will get an error.
function ByteBuffer:writeByte(byteValue)
    local str = string.pack("b", byteValue)
    self:writeBuffer(str)
    return self
end

function ByteBuffer:readByte()
    local result = string.unpack("b", self:readRawByteStr())
    return result
end

-- The byte is a number between 0 and 255, otherwise, the lua will get an error.
function ByteBuffer:writeUByte(ubyteValue)
    self:writeRawByteStr(string.char(ubyteValue))
    return self
end

function ByteBuffer:readUByte()
    return string.byte(self:readRawByteStr())
end


-- short
function ByteBuffer:writeShort(shortValue)
    local str = string.pack(">h", shortValue)
    self:writeBuffer(str)
    return self
end

function ByteBuffer:readShort()
    local byteStrArray = self:readBuffer(2)
    local result = string.unpack(">h", byteStrArray)
    return result
end


-- int
function ByteBuffer:writeInt(intValue)
    if (math.type(intValue) ~= "integer") then
        error("intValue must be integer")
    end
    if ((minInt > intValue) or (intValue > maxInt)) then
        error("intValue must range between minInt:-2147483648 and maxInt:2147483647")
    end

    return self:writeLong(intValue)
end

function ByteBuffer:readInt()
    return self:readLong()
end

-- int
function ByteBuffer:writeRawInt(intValue)
    local str = string.pack(">i", intValue)
    self:writeBuffer(str)
    return self
end

function ByteBuffer:readRawInt()
    local byteStrArray = self:readBuffer(4)
    local result = string.unpack(">i", byteStrArray)
    return result
end

--long
function ByteBuffer:writeLong(longValue)
    --Long:writeLong(self, longValue)

    if (math.type(longValue) ~= "integer") then
        error("longValue must be integer")
    end

    --lua中的右移为无符号右移，要特殊处理
    local mask = longValue >> 63
    local value = longValue << 1
    if (mask == 1) then
        value = value ~ 0xFFFFFFFFFFFFFFFF
    end

    if (value >> 7) == 0 then
        self:writeUByte(value)
        return
    end

    if (value >> 14) == 0 then
        self:writeUByte(value & 0x7F | 0x80)
        self:writeUByte((value >> 7) & 0x7F)
        return
    end

    if (value >> 21) == 0 then
        self:writeUByte((value & 0x7F) | 0x80)
        self:writeUByte(((value >> 7) & 0x7F | 0x80))
        self:writeUByte((value >> 14) & 0x7F)
        return
    end

    if (value >> 28) == 0 then
        self:writeUByte(value & 0x7F | 0x80)
        self:writeUByte(((value >> 7) & 0x7F | 0x80))
        self:writeUByte(((value >> 14) & 0x7F | 0x80))
        self:writeUByte((value >> 21) & 0x7F)
        return
    end

    if (value >> 35) == 0 then
        self:writeUByte(value & 0x7F | 0x80)
        self:writeUByte(((value >> 7) & 0x7F | 0x80))
        self:writeUByte(((value >> 14) & 0x7F | 0x80))
        self:writeUByte(((value >> 21) & 0x7F | 0x80))
        self:writeUByte((value >> 28) & 0x7F)
        return
    end

    if (value >> 42) == 0 then
        self:writeUByte(value & 0x7F | 0x80)
        self:writeUByte(((value >> 7) & 0x7F | 0x80))
        self:writeUByte(((value >> 14) & 0x7F | 0x80))
        self:writeUByte(((value >> 21) & 0x7F | 0x80))
        self:writeUByte(((value >> 28) & 0x7F | 0x80))
        self:writeUByte((value >> 35) & 0x7F)
        return
    end

    if (value >> 49) == 0 then
        self:writeUByte(value & 0x7F | 0x80)
        self:writeUByte(((value >> 7) & 0x7F | 0x80))
        self:writeUByte(((value >> 14) & 0x7F | 0x80))
        self:writeUByte(((value >> 21) & 0x7F | 0x80))
        self:writeUByte(((value >> 28) & 0x7F | 0x80))
        self:writeUByte(((value >> 35) & 0x7F | 0x80))
        self:writeUByte((value >> 42) & 0x7F)
        return
    end

    if (value >> 56) == 0 then
        self:writeUByte(value & 0x7F | 0x80)
        self:writeUByte(((value >> 7) & 0x7F | 0x80))
        self:writeUByte(((value >> 14) & 0x7F | 0x80))
        self:writeUByte(((value >> 21) & 0x7F | 0x80))
        self:writeUByte(((value >> 28) & 0x7F | 0x80))
        self:writeUByte(((value >> 35) & 0x7F | 0x80))
        self:writeUByte(((value >> 42) & 0x7F | 0x80))
        self:writeUByte((value >> 49) & 0x7F)
        return
    end

    self:writeUByte(value & 0x7F | 0x80)
    self:writeUByte(((value >> 7) & 0x7F | 0x80))
    self:writeUByte(((value >> 14) & 0x7F | 0x80))
    self:writeUByte(((value >> 21) & 0x7F | 0x80))
    self:writeUByte(((value >> 28) & 0x7F | 0x80))
    self:writeUByte(((value >> 35) & 0x7F | 0x80))
    self:writeUByte(((value >> 42) & 0x7F | 0x80))
    self:writeUByte(((value >> 49) & 0x7F | 0x80))
    self:writeUByte(value >> 56)
    return self
end

function ByteBuffer:readLong()
    --return Long:readLong(self):toString()
    local b = self:readUByte()
    local value = b & 0x7F
    if (b & 0x80) ~= 0 then
        b = self:readUByte()
        value = value | ((b & 0x7F) << 7)
        if (b & 0x80) ~= 0 then
            b = self:readUByte()
            value = value | ((b & 0x7F) << 14)
            if (b & 0x80) ~= 0 then
                b = self:readUByte()
                value = value | ((b & 0x7F) << 21)
                if (b & 0x80) ~= 0 then
                    b = self:readUByte()
                    value = value | ((b & 0x7F) << 28)
                    if (b & 0x80) ~= 0 then
                        b = self:readUByte()
                        value = value | ((b & 0x7F) << 35)
                        if (b & 0x80) ~= 0 then
                            b = self:readUByte()
                            value = value | ((b & 0x7F) << 42)
                            if (b & 0x80) ~= 0 then
                                b = self:readUByte()
                                value = value | ((b & 0x7F) << 49)
                                if (b & 0x80) ~= 0 then
                                    b = self:readUByte()
                                    value = value | (b << 56)
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return (value >> 1) ~ -(value & 1)
end

--固定8位的lua数字类型
function ByteBuffer:writeLuaNumber(luaNumberValue)
    local str = string.pack(">n", luaNumberValue)
    self:writeBuffer(str)
    return self
end

function ByteBuffer:readLuaNumber()
    local result = string.unpack(">n", self:readBuffer(8))
    return result
end




--float
function ByteBuffer:writeFloat(floatValue)
    local str = string.pack(">f", floatValue)
    self:writeBuffer(str)
    return self
end

function ByteBuffer:readFloat()
    local byteStrArray = self:readBuffer(4)
    local result = string.unpack(">f", byteStrArray)
    return result
end


--double
function ByteBuffer:writeDouble(doubleValue)
    local str = string.pack(">d", doubleValue)
    self:writeBuffer(str)
    return self
end

function ByteBuffer:readDouble()
    local byteStrArray = self:readBuffer(8)
    local result = string.unpack(">d", byteStrArray)
    return result
end


--string
function ByteBuffer:writeString(str)
    if str == nil or #str == 0 then
        self:writeInt(0)
        return
    end
    self:writeInt(#str)
    self:writeBuffer(str)
    return self
    end

function ByteBuffer:readString()
    local length = self:readInt()
    return self:readBuffer(length)
end

--char
function ByteBuffer:writeChar(charValue)
    if str == nil or #str == 0 then
        self:writeInt(0)
        self:writeByte(0)
        return
    end
    local str = utf8sub(charValue, 1, 1)
    self:writeString(str)
    return self
end

function ByteBuffer:readChar()
    return self:readString()
end

--- Write a encoded char array into buf
function ByteBuffer:writeBuffer(str)
    for i = 1, #str do
        self:writeRawByteStr(string.sub(str, i, i))
    end
    return self
end

--- Read a byte array as string from current position, then update the position.
function ByteBuffer:readBuffer(length)
    local byteStrArray = self:getBytes(self.readOffset, self.readOffset + length - 1)
    self.readOffset = self.readOffset + length
    return byteStrArray
end

function ByteBuffer:writeRawByteStr(byteStrValue)
    if self.writeOffset > #self.buffer + 1 then
        for i = #self.buffer + 1, self.writeOffset - 1 do
            table.insert(self.buffer, zeroByte)
        end
    end
    self.buffer[self.writeOffset] = string.sub(byteStrValue, 1, 1)
    self.writeOffset = self.writeOffset + 1
    return self
end

function ByteBuffer:readRawByteStr()
    local byteStrValue = self.buffer[self.readOffset]
    self.readOffset = self.readOffset + 1
    return byteStrValue
end

--- Get all byte array as a lua string.
-- Do not update position.
function ByteBuffer:getBytes(startIndex, endIndex)
    startIndex = startIndex or 1
    endIndex = endIndex or #self.buffer
    return table.concat(self.buffer, "", startIndex, endIndex)
end

return ByteBuffer