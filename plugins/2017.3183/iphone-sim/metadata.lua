local metadata =
{
	plugin =
	{
		format = "staticLibrary",

		-- This is the name without the 'lib' prefix.
		-- In this case, the static library is called: libSTATIC_LIB_NAME.a
		staticLibs = { "AdColonyPlugin", }, 

		frameworks = { "AdColony", "AdSupport", "CoreTelephony", "EventKit", "EventKitUI", "Social", "StoreKit" },
		frameworksOptional = {"JavaScriptCore", "WatchConnectivity", "WebKit", "AppTrackingTransparency" },
	}
}

return metadata
