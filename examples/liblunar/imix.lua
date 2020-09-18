
PktSize = { 
  -- Used if size is static. 
  -- Size in octets of the Layer 2 ethernet frame to be sent.
  -- It includes the CRC and must therefore be between 64-1552 for 
  -- regular sized packets.
  size = 0, 

  -- Used to represent internet mixes with different packet sizes.
  -- Is a list of sizes like self.size. 
  imix = {}
}

function PktSize:static(pktSize)
  self.size = pktSize
end
