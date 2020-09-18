
Luna = {
	rxDev = 0,
  rxPort = 0,
	txDev = 0,
  txPort = 0,
  threads = 0,
}

function configure(parser)
  parser:description("Generates CBR traffic with hardware rate control")
  parser:argument("txDev", "Device id to send from."):convert(tonumber)
  parser:argument("rxDev", "Device id to recieve from."):convert(tonumber)
  parser:option("--ethSrc", "Source eth addr."):default("00:11:22:33:44:55"):convert(tostring)
  parser:option("-d --ethDst", "Target eth addr. (network BO if using --macs)"):default("00:00:00:00:00:00"):convert(tostring)
  parser:option("-s --pktSize", "Packet size."):default(60):convert(tonumber)
  parser:option("-r --rate", "Transmit rate in Mbit/s."):default(10000):convert(tonumber)
  parser:option("-m --macs", "Send to (ethDst...ethDst+macs)."):default(0):convert(tonumber)
  parser:option("-h --hifile", "Filename for the latency histogram."):default("histogram.csv")
  parser:option("-t --thfile", "Filename for the throughput csv file."):default("throuput.csv")
  parser:option("-l --lafile", "Filename for latency summary file."):default("latency.csv")
  parser:option("-i --lalifile", "Filename for latencies per packet file."):default("latencies.csv")
end

-- blocks until links are up
-- threads: nr. of thread to send with
-- stats: bool: whether to print throughput stats to stdout
function Luna:start_devices(txPort, rxPort, threads, stats)
  self.txPort = txPort
  self.rxPort = rxPort
  self.threads = threads

  if pattern == "cbr" and threads ~= 1 then
      return log:error("cbr only supports one thread")
  end

  self.txDev = device.config{port = txPort, txQueues = threads, disableOffloads = rc ~= "moongen"}
  self.rxDev = device.config{port = rxPort}

  if stats then
    stats.startStatsTask{self.txDev, self.rxDev}
  end

	device.waitForLinks()
  return self
end

-- blocks until first successfull transmission
-- pktFn: buffer -> (): fills buffer with data
--        example: local pktFn = function(buf)
--            fillEthPacket(buf, args.ethSrc, args.ethDst)
--        end
-- timeout: us: how long to wait for a packet to arrive before timeouting
function Luna:warmup_link(pktFn, timeout)
  local recTask = mg.startTask("rxWarmup", rxDev:getRxQueue(0), timeout)
  txWarmup(recTask, txDev:getTxQueue(0), pktFn, args.pktSize)
  mg.waitForTasks()
end

-- blocks until test has finished
-- rate: Send rate in MBit/sec. All bits serialized onto the physical wire are counted.
-- rc: rate control mechanism: hw|sw|moongen
-- pattern: inter packet gap pattern: cbr|poisson|custom
-- pktSize: imix::PktSize.  
function Luna:run_test(rate, rc, pattern, pktSize, pktFn)
  for i = 1, self.threads do
		local rateLimiter
		if rc == "sw" then
			rateLimiter = limiter:new(txDev:getTxQueue(i - 1), pattern, 1 / rate * 1000)
		end
		mg.startTask("loadSlave", txDev:getTxQueue(i - 1), txDev, rate, rc, pattern, rateLimiter, i, self.threads, pktFn)
	end
end

