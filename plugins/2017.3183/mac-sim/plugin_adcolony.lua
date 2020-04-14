-- AdColony plugin

local Library = require "CoronaLibrary"

-- Create library
local lib = Library:new{ name="plugin.adcolony", publisherId="com.coronalabs", version=2 }

-------------------------------------------------------------------------------
-- BEGIN
-------------------------------------------------------------------------------

-- This sample implements the following Lua:
-- 
--    local adcolony = require "plugin.adcolony"
--    adcolony.init()
--    

local function showWarning(functionName)
    print( functionName .. " WARNING: The AdColony plugin is only supported on iOS, Android and Amazon devices. Please build for device")
end

function lib.init()
    showWarning("adcolony.init()")
end

function lib.show()
    showWarning("adcolony.show()")
end

function lib.load()
    showWarning("adcolony.load()")
end

function lib.isLoaded()
    showWarning("adcolony.isLoaded()")
end

function lib.getInfoForZone()
    showWarning("adcolony.getInfoForZone()")
end

-------------------------------------------------------------------------------
-- END
-------------------------------------------------------------------------------

-- Return an instance
return lib
