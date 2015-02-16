local ffi = require "ffi"

require "utils"
require "headers"

local eth = require "proto.ethernet"

local ntoh, hton = ntoh, hton
local ntoh16, hton16 = ntoh16, hton16
local bswap = bswap
local bswap16 = bswap16
local bor, band, bnot, rshift, lshift= bit.bor, bit.band, bit.bnot, bit.rshift, bit.lshift
local istype = ffi.istype
local format = string.format

------------------------------------------------------------------------------------
--- IP6 constants
-- TODO nextHeader uses same constants as IP protocol -> use the values from ip.lua?
------------------------------------------------------------------------------------

local ip6 = {}

ip6.PROTO_TCP 	= 0x06
ip6.PROTO_UDP 	= 0x11
ip6.PROTO_ICMP	= 0x3a -- 58

-------------------------------------------------------------------------------------
--- IPv6 addresses
-------------------------------------------------------------------------------------

local ip6Addr = {}
ip6Addr.__index = ip6Addr
local ip6AddrType = ffi.typeof("union ipv6_address")

--- Retrieve the IPv6 address.
-- @return Address in 'union ipv6_address' format.
function ip6Addr:get()
	local addr = ip6AddrType()
	addr.uint32[0] = bswap(self.uint32[3])
	addr.uint32[1] = bswap(self.uint32[2])
	addr.uint32[2] = bswap(self.uint32[1])
	addr.uint32[3] = bswap(self.uint32[0])
	return addr
end

--- Set the IPv6 address.
-- @param addr Address in 'union ipv6_address' format.
function ip6Addr:set(addr)
	self.uint32[0] = bswap(addr.uint32[3])
	self.uint32[1] = bswap(addr.uint32[2])
	self.uint32[2] = bswap(addr.uint32[1])
	self.uint32[3] = bswap(addr.uint32[0])
end

--- Set the IPv6 address.
-- @param ip Address in string format.
function ip6Addr:setString(ip)
	self:set(parseIP6Address(ip))
end

--- Test equality of two IPv6 addresses.
-- @param lhs Address in 'union ipv6_address' format.
-- @param rhs Address in 'union ipv6_address' format.
-- @return true if equal, false otherwise.
function ip6Addr.__eq(lhs, rhs)
	return istype(ip6AddrType, lhs) and istype(ip6AddrType, rhs) and lhs.uint64[0] == rhs.uint64[0] and lhs.uint64[1] == rhs.uint64[1]
end

--- Add a number to an IPv6 address.
-- Max. 64bit, commutative.
-- @param lhs Address in 'union ipv6_address' format.
-- @param rhs Number to add (64 bit integer).
-- @return Resulting address in 'union ipv6_address' format.
function ip6Addr.__add(lhs, rhs)
	-- calc ip (self) + number (val)
	local self, val
	if istype(ip6AddrType, lhs) then
		self = lhs
		val = rhs
	else
		-- commutative for number + ip
		self = rhs
		val = lhs
	end -- TODO: ip + ip?
	local addr = ip6AddrType()
	local low, high = self.uint64[0], self.uint64[1]
	low = low + val
	-- handle overflow
	if low < val and val > 0 then
		high = high + 1
	-- handle underflow
	elseif low > -val and val < 0 then
		high = high - 1
	end
	addr.uint64[0] = low
	addr.uint64[1] = high
	return addr
end

--- Add a number to an IPv6 address in-place.
-- Max 64 bit.
-- @param val Number to add (64 bit integer).
function ip6Addr:add(val)
	-- calc ip (self) + number (val)
	local low, high = bswap(self.uint64[1]), bswap(self.uint64[0])
	low = low + val
	-- handle overflow
	if low < val and val > 0 then
		high = high + 1
	-- handle underflow
	elseif low > -val and val < 0 then
		high = high - 1
	end
	self.uint64[1] = bswap(low)
	self.uint64[0] = bswap(high)
end

--- Subtract a number from an IPv6 address.
-- Max. 64 bit.
-- @param val Number to substract (64 bit integer).
-- @return Resulting address in 'union ipv6_address' format.
function ip6Addr:__sub(val)
	return self + -val
end

-- Retrieve the string representation of an IPv6 address.
-- Assumes 'union ipv6_address' is in network byteorder.
-- @param doByteSwap Optional change the byteorder of the ip6 address before returning the string representation.
-- @return Address in string format.
function ip6Addr:getString(doByteSwap)
	doByteSwap = doByteSwap or false
	if doByteSwap then
		self = self:get()
	end

	return ("%02x%02x:%02x%02x:%02x%02x:%02x%02x:%02x%02x:%02x%02x:%02x%02x:%02x%02x"):format(
			self.uint8[0], self.uint8[1], self.uint8[2], self.uint8[3], 
			self.uint8[4], self.uint8[5], self.uint8[6], self.uint8[7], 
			self.uint8[8], self.uint8[9], self.uint8[10], self.uint8[11], 
			self.uint8[12], self.uint8[13], self.uint8[14], self.uint8[15]
			)
end


------------------------------------------------------------------------------
--- IPv6 header
------------------------------------------------------------------------------

local ip6Header = {}
ip6Header.__index = ip6Header

--- Set the version. 
-- @param int IP6 header version as 4 bit integer. Should always be '6'.
function ip6Header:setVersion(int)
	int = int or 6
	int = band(lshift(int, 28), 0xf0000000) -- fill to 32 bits
	
	old = bswap(self.vtf)
	old = band(old, 0x0fffffff)	-- remove old value
	
	self.vtf = bswap(bor(old, int))
end

--- Retrieve the version.
-- @return Version as 4 bit integer.
function ip6Header:getVersion()
	return band(rshift(bswap(self.vtf), 28), 0x0000000f)
end

--- Retrieve the version.
-- @return Version as string.
function ip6Header:getVersionString()
	return self:getVersion()
end

--- Set the traffic class.
-- @param int Traffic class of the ip6 header as 8 bit integer.
function ip6Header:setTrafficClass(int)
	int = int or 0
	int = band(lshift(int, 20), 0x0ff00000)
	
	old = bswap(self.vtf)
	old = band(old, 0xf00fffff)
	
	self.vtf = bswap(bor(old, int))
end

--- Retrieve the traffic class.
-- @return Traffic class as 8 bit integer.
function ip6Header:getTrafficClass()
	return band(rshift(bswap(self.vtf), 20), 0x000000ff)
end

--- Retrieve the traffic class.
-- @return Traffic class as string.
function ip6Header:getTrafficClassString()
	return self:getTrafficClass()
end

--- Set the flow label.
-- @param int Flow label of the ip6 header as 20 bit integer.
function ip6Header:setFlowLabel(int)
	int = int or 0
	int = band(int, 0x000fffff)
	
	old = bswap(self.vtf)
	old = band(old, 0xfff00000)
	
	self.vtf = bswap(bor(old, int))
end

--- Retrieve the flow label.
-- @return Flow label as 20 bit integer.
function ip6Header:getFlowLabel()
	return band(bswap(self.vtf), 0x000fffff)
end

--- Retrieve the flow label.
-- @return Flow label as string.
function ip6Header:getFlowLabelString()
	return self:getFlowLabel()
end

--- Set the payload length.
-- @param int Length of the ip6 header payload (hence, excluding l2 and l3 headers). 16 bit integer.
function ip6Header:setLength(int)
	int = int or 8	-- with eth + UDP -> minimum 66
	self.len = hton16(int)
end

--- Retrieve the length.
-- @return Length as 16 bit integer.
function ip6Header:getLength()
	return hton16(self.len)
end

--- Retrieve the length.
-- @return Length as string.
function ip6Header:getLengthString()
	return self:getLength()
end

--- Set the next header.
-- @param int Next header of the ip6 header as 8 bit integer.
function ip6Header:setNextHeader(int)
	int = int or ip6.PROTO_UDP
	self.nextHeader = int
end

--- Retrieve the next header.
-- @return Next header as 8 bit integer.
function ip6Header:getNextHeader()
	return self.nextHeader
end

--- Retrieve the next header.
-- @return Next header as string.
function ip6Header:getNextHeaderString()
	local proto = self:getNextHeader()
	local cleartext = ""

	if proto == ip6.PROTO_ICMP then
		cleartext = "(ICMP)"
	elseif proto == ip6.PROTO_UDP then
		cleartext = "(UDP)"
	elseif proto == ip6.PROTO_TCP then
		cleartext = "(TCP)"
	else
		cleartext = "(unknown)"
	end
	
	return format("0x%02x %s", proto, cleartext)
end

--- Set the time-to-live (TTL).
-- @param int TTL of the ip6 header as 8 bit integer.
function ip6Header:setTTL(int)
	int = int or 64
	self.ttl = int
end

--- Retrieve the time-to-live.
-- @return TTL as 8 bit integer.
function ip6Header:getTTL()
	return self.ttl
end

--- Retrieve the time-to-live.
-- @return TTL as string.
function ip6Header:getTTLString()
	return self:getTTL()
end

--- Set the destination address.
-- @param addr Address in 'union ipv6_address' format.
function ip6Header:setDst(addr)
	self.dst:set(addr)
end

--- Retrieve the IP6 destination address.
-- @return Address in 'union ipv6_address' format.
function ip6Header:getDst()
	return self.dst:get()
end

--- Set the source  address.
-- @param addr Address in 'union ipv6_address' format.
function ip6Header:setSrc(addr)
	self.src:set(addr)
end

--- Retrieve the IP6 source address.
-- @return Address in 'union ipv6_address' format.
function ip6Header:getSrc()
	return self.src:get()
end

--- Set the destination address.
-- @param str Address in string format.
function ip6Header:setDstString(str)
	self:setDst(parseIP6Address(str))
end

--- Retrieve the IP6 destination address.
-- @return Address in string format.
function ip6Header:getDstString()
	return self.dst:getString()
end

--- Set the source address.
-- @param str Address in string format.
function ip6Header:setSrcString(str)
	self:setSrc(parseIP6Address(str))
end

--- Retrieve the IP6 source address.
-- @return Address in source format.
function ip6Header:getSrcString()
	return self.src:getString()
end

--- Set all members of the ip6 header.
-- Per default, all members are set to default values specified in the respective set function.
-- Optional named arguments can be used to set a member to a user-provided value.
-- @param args Table of named arguments. Available arguments: ip6Version, ip6TrafficClass, ip6FlowLabel, ip6Length, ip6NextHeader, ip6TTL, ip6Src, ip6Dst
-- @usage fill() -- only default values
-- @usage fill{ ip6Src="f880::ab", ip6TTL=101 } -- all members are set to default values with the exception of ip6Src and ip6TTL
function ip6Header:fill(args)
	args = args or {}

	self:setVersion(args.ip6Version)
	self:setTrafficClass(args.ip6TrafficClass)
	self:setFlowLabel(args.ip6FlowLabel)
	self:setLength(args.ip6Length)
	self:setNextHeader(args.ip6NextHeader)
	self:setTTL(args.ip6TTL)
	
	args.ip6Src = args.ip6Src or "fe80::1"
	args.ip6Dst = args.ip6Dst or "fe80::2"	
	
	-- if for some reason the address is in 'union ipv6_address' format, cope with it
	if type(args.ip6Src) == "string" then
		self:setSrcString(args.ip6Src)
	else
		self:setSrc(args.ip6Src)
	end
	if type(args.ip6Dst) == "string" then
		self:setDstString(args.ip6Dst)
	else
		self:setDst(args.ip6Dst)
	end
end

--- Retrieve the values of all members.
-- @return Table of named arguments. For a list of arguments see "See also".
-- @see ip6Header:fill
function ip6Header:get()
	return { ip6Src=self:getSrcString(), ip6Dst=self:getDstString(), ip6Version=self:getVersion(), ip6TrafficClass=self:getTrafficClass(), 
			 ip6FlowLabel=self:getFlowLabel(), ip6Length=self:getLength(), ip6NextHeader=self:getNextHeader(), ip6TTL=self:getTTL() }
end

--- Retrieve the values of all members.
-- @return Values in string format.
function ip6Header:getString()
	return "IP6 " .. self:getSrcString() .. " > " .. self:getDstString() .. " ver " .. self:getVersionString() 
		   .. " tc " .. self:getTrafficClassString() .. " fl " .. self:getFlowLabelString() .. " len " .. self:getLengthString() 
		   .. " next " .. self:getNextHeaderString() .. " ttl " .. self:getTTLString()
end


--------------------------------------------------------------------------------------------
--- IPv6 packets
--------------------------------------------------------------------------------------------

local ip6Packet = {}
ip6Packet.__index = ip6Packet

--- Set all members of all headers.
-- Per default, all members are set to default values specified in the respective set function.
-- Optional named arguments can be used to set a member to a user-provided value.
-- The argument 'pktLength' can be used to automatically calculate and set the length member of the ip6 header.
-- @param args Table of named arguments. For a list of available arguments see "See also"
-- @usage fill() -- only default values
-- @usage fill{ ethSrc="12:23:34:45:56:67", ip6TTL=100 } -- all members are set to default values with the exception of ethSrc and ip6TTL
-- @usage fill{ pktLength=64 } -- only default values, ip6Length is set to the respective value
-- @see etherHeader:fill
-- @see ip6Header:fill
function ip6Packet:fill(args)
	args = args or {}
	
	-- calculate length value for ip headers
	if args.pktLength then
		args.ip6Length = args.ip6Length or args.pktLength - (14 + 40) -- ethernet + ip
	end
	
	-- change default value for ipv6
	args.ethType = args.ethType or eth.TYPE_IP6

	self.eth:fill(args)
	self.ip:fill(args)
end

--- Retrieve the values of all members.
-- @return Table of named arguments. For a list of arguments see "See also".
-- @see etherHeader:get
-- @see ip6Header:get
function ip6Packet:get()
	return mergeTables(self.eth:get(), self.ip:get())
end

--- Print information about the headers and a hex dump of the complete packet.
-- @param bytes Number of bytes to dump.
function ip6Packet:dump(bytes)
	dumpPacket(self, bytes, self.eth, self.ip)
end


------------------------------------------------------------------------
--- Metatypes
------------------------------------------------------------------------

ffi.metatype("union ipv6_address", ip6Addr)
ffi.metatype("struct ipv6_header", ip6Header)
ffi.metatype("struct ip_v6_packet", ip6Packet)

return ip6
