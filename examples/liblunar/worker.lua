
-- recTask is only usable in master thread
-- pktFn: buffer -> (): fills buffer with data
--        example: local pktFn = function(buf)
--            fillEthPacket(buf, args.ethSrc, args.ethDst)
--        end
function txWarmup(recTask, txQueue, pktFn, pktSize)
  local mem = memory.createMemPool(pktFn)
  local bufs = mem:bufArray(1)
  mg.sleepMillis(1000) -- ensure that waitWarmup is listening
  while recTask:isRunning() do
    bufs:alloc(pktSize)
    txQueue:send(bufs)
    log:info("warmup packet sent")
    mg.sleepMillis(1500)
  end
end

function rxWarmup(rxQueue, timeout)
	local bufs = memory.bufArray(128)

	log:info("waiting for first successful packet...")
	local rx = rxQueue:tryRecv(bufs, timeout)
	bufs:freeAll()
	if rx <= 0 then
		log:fatal("no packet could be received!")
	else
		log:info("first packet received")
	end
end

function loadSlave(queue, txDev, rate, rc, pattern, rateLimiter, threadId, numThreads, pktFn)
	local mem = memory.createMemPool(4096, pktFn)
	if rc == "hw" then
		local bufs = mem:bufArray()
		if pattern ~= "cbr" then
			return log:error("HW only supports CBR")
		end
		queue:setRate(rate * (PKT_SIZE + 4) * 8)
		mg.sleepMillis(100) -- for good meaasure
		while mg.running() do
			bufs:alloc(PKT_SIZE)
			queue:send(bufs)
		end
	elseif rc == "sw" then
		-- larger batch size is useful when sending it through a rate limiter
		local bufs = mem:bufArray(128)
		local linkSpeed = txDev:getLinkStatus().speed
		while mg.running() do
			bufs:alloc(PKT_SIZE)
			if pattern == "custom" then
				for _, buf in ipairs(bufs) do
					buf:setDelay(rate * linkSpeed / 8)
				end
			end
			rateLimiter:send(bufs)
		end
	elseif rc == "moongen" then
		-- larger batch size is useful when sending it through a rate limiter
		local bufs = mem:bufArray(128)
		local dist = pattern == "poisson" and poissonDelay or function(x) return x end
		while mg.running() do
			bufs:alloc(PKT_SIZE)
			for _, buf in ipairs(bufs) do
				buf:setDelay(dist(10^10 / numThreads / 8 / (rate * 10^6) - PKT_SIZE - 24))
			end
			queue:sendWithDelay(bufs, rate * numThreads)
		end
	else
		log:error("Unknown rate control method")
	end
end

function timerSlave(txQueue, rxQueue, histfile)
	local timestamper = ts:newTimestamper(txQueue, rxQueue)
	local hist = hist:new()
	mg.sleepMillis(1000) -- ensure that the load task is running
	while mg.running() do
		hist:update(timestamper:measureLatency(function(buf) buf:getEthernetPacket().eth.dst:setString(ETH_DST) end))
	end
	hist:print()
	hist:save(histfile)
end

