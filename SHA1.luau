local SHA1 = {}

local function leftRotate(n, bits)
	return bit32.lrotate(n, bits)
end

local function toHex(n)
	return string.format("%08x", n)
end

local function stringToBytes(str)
	local bytes = {}
	for i = 1, #str do
		bytes[i] = string.byte(str, i)
	end
	return bytes
end

local function bytesToString(bytes)
	local chars = {}
	for i = 1, #bytes do
		chars[i] = string.char(bytes[i])
	end
	return table.concat(chars)
end

local function preprocess(bytes)
	local ml = #bytes * 8
	local paddedLength = math.ceil((ml + 65) / 512) * 64
	local blocks = {}
	
	for i = 1, paddedLength do
		blocks[i] = 0
	end
	
	for i = 1, #bytes do
		local byteIndex = math.floor((i - 1) / 4) + 1
		local shift = 24 - ((i - 1) % 4) * 8
		blocks[byteIndex] = bit32.bor(blocks[byteIndex], bit32.lshift(bytes[i], shift))
	end
	
	local bitIndex = #bytes
	local byteIndex = math.floor(bitIndex / 4) + 1
	local shift = 24 - (bitIndex % 4) * 8
	blocks[byteIndex] = bit32.bor(blocks[byteIndex], bit32.lshift(0x80, shift))
	
	blocks[paddedLength - 1] = math.floor(ml / 0x100000000)
	blocks[paddedLength] = ml % 0x100000000
	
	return blocks
end

function SHA1.hash(message)
	local bytes = stringToBytes(message)
	local blocks = preprocess(bytes)
	
	local h0 = 0x67452301
	local h1 = 0xEFCDAB89
	local h2 = 0x98BADCFE
	local h3 = 0x10325476
	local h4 = 0xC3D2E1F0
	
	for i = 1, #blocks, 16 do
		local w = {}
		
		for j = 0, 15 do
			w[j] = blocks[i + j]
		end
		
		for j = 16, 79 do
			w[j] = leftRotate(bit32.bxor(w[j-3], w[j-8], w[j-14], w[j-16]), 1)
		end
		
		local a = h0
		local b = h1
		local c = h2
		local d = h3
		local e = h4
		
		for j = 0, 79 do
			local f, k
			
			if j < 20 then
				f = bit32.bor(bit32.band(b, c), bit32.band(bit32.bnot(b), d))
				k = 0x5A827999
			elseif j < 40 then
				f = bit32.bxor(b, c, d)
				k = 0x6ED9EBA1
			elseif j < 60 then
				f = bit32.bor(bit32.band(b, c), bit32.band(b, d), bit32.band(c, d))
				k = 0x8F1BBCDC
			else
				f = bit32.bxor(b, c, d)
				k = 0xCA62C1D6
			end
			
			local temp = (leftRotate(a, 5) + f + e + k + w[j]) % 0x100000000
			e = d
			d = c
			c = leftRotate(b, 30)
			b = a
			a = temp
		end
		
		h0 = (h0 + a) % 0x100000000
		h1 = (h1 + b) % 0x100000000
		h2 = (h2 + c) % 0x100000000
		h3 = (h3 + d) % 0x100000000
		h4 = (h4 + e) % 0x100000000
	end
	
	return toHex(h0) .. toHex(h1) .. toHex(h2) .. toHex(h3) .. toHex(h4)
end

function SHA1.hmac(key, message)
	local blockSize = 64
	
	local keyBytes = stringToBytes(key)
	
	if #keyBytes > blockSize then
		local hashed = SHA1.hash(key)
		keyBytes = {}
		for i = 1, #hashed, 2 do
			table.insert(keyBytes, tonumber(string.sub(hashed, i, i+1), 16))
		end
	end
	
	local paddedKey = {}
	for i = 1, blockSize do
		paddedKey[i] = keyBytes[i] or 0
	end
	
	local ipad = {}
	local opad = {}
	
	for i = 1, blockSize do
		ipad[i] = bit32.bxor(paddedKey[i], 0x36)
		opad[i] = bit32.bxor(paddedKey[i], 0x5C)
	end
	
	local messageBytes = stringToBytes(message)
	local innerMessage = {}
	
	for i = 1, blockSize do
		table.insert(innerMessage, ipad[i])
	end
	for i = 1, #messageBytes do
		table.insert(innerMessage, messageBytes[i])
	end
	
	local innerHash = SHA1.hash(bytesToString(innerMessage))
	local innerHashBytes = {}
	for i = 1, #innerHash, 2 do
		table.insert(innerHashBytes, tonumber(string.sub(innerHash, i, i+1), 16))
	end
	
	local outerMessage = {}
	for i = 1, blockSize do
		table.insert(outerMessage, opad[i])
	end
	for i = 1, #innerHashBytes do
		table.insert(outerMessage, innerHashBytes[i])
	end
	
	return SHA1.hash(bytesToString(outerMessage))
end

function SHA1.compare(hash1, hash2)
	if #hash1 ~= #hash2 then
		return false
	end
	
	local result = true
	for i = 1, #hash1 do
		if string.sub(hash1, i, i) ~= string.sub(hash2, i, i) then
			result = false
		end
	end
	
	return result
end

function SHA1.hashFile(content)
	return SHA1.hash(content)
end

function SHA1.verify(message, expectedHash)
	local actualHash = SHA1.hash(message)
	return SHA1.compare(actualHash, expectedHash)
end

return SHA1
