local ffi = require("ffi")
local C = ffi.C
ffi.cdef [[
	const char* GetComponentClass(UniverseID componentid);
	const char* GetObjectIDCode(UniverseID objectid);
]]

local MKLuaData = {}

DebugError("Creating MKLuaData")

function MKLuaData.init()
	DebugError("Running MKLuaData init")
	RegisterEvent("mkPollWareData", MKLuaData.mkPollWareData)
end

function MKLuaData.mkPollWareData(_, param)
	local stationKeys = {}

	local wareResource = {}
	local wareCount = {}
	local wareProdTime = {}
	local wareProdAmount = {}
	local wareProdTotal = {}
	local faction, firmName = param:match("%[(.+)%]"):match("(.+)/(.+)")
	local scrubbed = param:gsub("%[.+%]", "")

	for key, value in scrubbed:gmatch("(%w+):(.-[;])") do
		local component = ConvertStringToLuaID(ConvertIDTo64Bit(tostring(key)))
		wareCount[component] = {}
		wareResource[component] = {}
		wareProdTime[component] = {}
		wareProdAmount[component] = {}
		wareProdTotal[component] = {}

		for warepair in value:gmatch("[^,;]+") do
			for ware, total in warepair:gmatch("(%w+)=(%w+)") do
				if wareCount[component][ware] == nil then
					wareCount[component][ware] = 0
				end
				if wareProdTotal[component][ware] == nil then
					wareProdTotal[component][ware] = 0
				end
				wareCount[component][ware] = wareCount[component][ware] + 1
				wareProdTotal[component][ware] = wareProdTotal[component][ware] + total
				wareResource[component][ware], wareProdTime[component][ware], wareProdAmount[component][ware] =
					GetWareData(
						ware, "resources",
						"productiontime",
						"productionamount")
			end
		end
		stationKeys[component] = { wareResource[component], wareProdTime[component], wareProdAmount[component], wareCount
			[component], wareProdTotal[component] }
	end

	SignalObject(ConvertStringTo64Bit(tostring(C.GetPlayerID())), "mk_poll_signalling", firmName, stationKeys)
end

MKLuaData.init()
