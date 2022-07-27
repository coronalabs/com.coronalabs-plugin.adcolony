//
//  AdColonyPlugin.mm
//  AdColony Plugin
//
//  Copyright (c) 2016 Corona Labs Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// Corona
#import "CoronaRuntime.h"
#import "CoronaAssert.h"
#import "CoronaEvent.h"
#import "CoronaLua.h"
#import "CoronaLibrary.h"
#import "CoronaLuaIOS.h"

// AdColony
#import "AdColonyPlugin.h"
#import <AdColony/AdColony.h>

// some macros to make life easier, and code more readable
#define UTF8StringWithFormat(format, ...) [[NSString stringWithFormat:format, ##__VA_ARGS__] UTF8String]
#define UTF8IsEqual(utf8str1, utf8str2) (strcmp(utf8str1, utf8str2) == 0)
#define UTF8Concat(utf8str1, utf8str2) [[NSString stringWithFormat:@"%s%s", utf8str1, utf8str2] UTF8String]
#define MsgFormat(format, ...) [NSString stringWithFormat:format, ##__VA_ARGS__]

// used to declare no data for numeric params
#define NO_DATA INT_MAX

// ----------------------------------------------------------------------------
// Plugin Constants
// ----------------------------------------------------------------------------

#define PLUGIN_NAME        "plugin.adcolony"
#define PLUGIN_VERSION     "2.2.0"
#define PLUGIN_SDK_VERSION [AdColony getSDKVersion]

static const char EVENT_NAME[]    = "adsRequest";
static const char PROVIDER_NAME[] = "adcolony";

// event phases
static NSString * const PHASE_INIT      = @"init";
static NSString * const PHASE_INFO      = @"info";
static NSString * const PHASE_LOADED    = @"loaded";
static NSString * const PHASE_FAILED    = @"failed";
static NSString * const PHASE_CLICKED   = @"clicked";
static NSString * const PHASE_DISPLAYED = @"displayed";
static NSString * const PHASE_CLOSED    = @"closed";
static NSString * const PHASE_EXPIRED   = @"expired";
static NSString * const PHASE_REWARD    = @"reward";

// message constants
static NSString * const ERROR_MSG   = @"ERROR: ";
static NSString * const WARNING_MSG = @"WARNING: ";

// missing Corona Event Keys
static NSString * const CORONA_EVENT_DATA_KEY = @"data";

// key/value dictionary for ad objects
static NSMutableDictionary *adcolonyObjects;

// object dictionary keys
static NSString * const SDK_READY_KEY  = @"sdkReady";
static NSString * const APPID_KEY      = @"appID";
static NSString * const ZONETABLE_KEY  = @"zoneTable";
static NSString * const ZONESTATUS_KEY = @"zoneStatus";

// zone keys
static NSString * const ZONE_ID_KEY       = @"id";
static NSString * const ZONE_TYPE_KEY     = @"type";
static NSString * const ZONE_NAME_KEY     = @"name";
static NSString * const ZONE_LOADED_KEY   = @"loaded";
static NSString * const ZONE_ADOBJECT_KEY = @"adObject";

// ad types
static NSString * const TYPE_INTERSTITIAL  = @"interstitial";
static NSString * const TYPE_REWARDEDVIDEO = @"rewardedVideo";

// ad orientations
static const char PORTRAIT[]  = "portrait";
static const char LANDSCAPE[] = "landscape";

// Log messages to the console
void logMsg(lua_State *L, NSString* msgType, NSString* errorMsg);     // generic message logging
static NSString *functionSignature;                                   // used in logMsg to identify function

// ----------------------------------------------------------------------------
// plugin class and delegate definitions
// ----------------------------------------------------------------------------

@interface AdColonyCoronaDelegate: NSObject

@property (nonatomic, assign) CoronaLuaRef coronaListener;                         // Reference to the Lua listener
@property (nonatomic, assign) id<CoronaRuntime> coronaRuntime;                     // Pointer to the Lua state

- (void)dispatchLuaEvent:(NSDictionary *)dict;

// generic AdColony delegate methods
- (void)onAdColonyAdLoadedInZone:(NSString *)zoneID;
- (void)onAdColonyAdFailedInZone:(NSString *)zoneID error:(AdColonyAdRequestError *)error;
- (void)onAdColonyAdStartedInZone:(NSString *)zoneID;
- (void)onAdColonyAdFinishedInZone:(NSString *)zoneID;
- (void)onAdColonyAdClickedInZone:(NSString *)zoneID;
- (void)onAdColonyAdExpiredInZone:(NSString *)zoneID;
- (void)onAdColonyReward:(BOOL)success currencyName:(NSString *)currencyName currencyAmount:(int)amount inZone:(NSString *)zoneID;

@end

// ----------------------------------------------------------------------------
// Interstitial Delegate
// ----------------------------------------------------------------------------

@interface AdColonyInterstitialDel: NSObject <AdColonyInterstitialDelegate>

@property (nonatomic, assign) NSString * zoneId;

@end

// ----------------------------------------------------------------------------

class AdColonyPlugin
{
    public:
        typedef AdColonyPlugin Self;
        static const char kName[];
    
    public:
        static int Open(lua_State *L);
        static int Finalizer(lua_State *L);
        static Self *ToLibrary(lua_State *L);

    protected:
        AdColonyPlugin();
        bool Initialize(void *platformContext);

    public:
        static int init(lua_State *L);
        static int isLoaded(lua_State *L);
        static int show(lua_State *L);
        static int load(lua_State *L);
        static int getInfoForZone(lua_State *L);

    private: // internal helper functions
        static bool isSDKInitialized(lua_State *L);

    private:
        UIViewController *coronaViewController;                     // application's view controller
        UIWindow *coronaWindow;                                     // application's UIWindow
};

const char AdColonyPlugin::kName[] = PLUGIN_NAME;
AdColonyCoronaDelegate *adcolonyCoronaDelegate;                     // AdColony's delegate

// ----------------------------------------------------------------------------
// helper functions
// ----------------------------------------------------------------------------

// log message to console
void
logMsg(lua_State *L, NSString* msgType, NSString* errorMsg)
{
    NSString *functionID = [functionSignature copy];
    if (functionID.length > 0) {
        functionID = [functionID stringByAppendingString:@", "];
    }
    
    CoronaLuaLogPrefix(L, [msgType UTF8String], UTF8StringWithFormat(@"%@%@", functionID, errorMsg));
}

// check if SDK calls can be made
bool
AdColonyPlugin::isSDKInitialized(lua_State *L)
{
    if (adcolonyCoronaDelegate.coronaListener == NULL) {
        logMsg(L, ERROR_MSG, @"adcolony.init() must be called before calling other API functions");
        return false;
    }
    
    if (! [adcolonyObjects[SDK_READY_KEY] boolValue]) {
        logMsg(L, ERROR_MSG, @"Please wait for the 'init' event before calling other API functions");
        return false;
    }

    return true;
}

// ----------------------------------------------------------------------------
// plugin implementation
// ----------------------------------------------------------------------------

int
AdColonyPlugin::Open(lua_State *L)
{
	// Register __gc callback
	const char kMetatableName[] = __FILE__; // Globally unique string to prevent collision
	CoronaLuaInitializeGCMetatable(L, kMetatableName, Finalizer);
	
	void *platformContext = CoronaLuaGetContext(L);

	// Set library as upvalue for each library function
	Self *library = new Self;

	if (library->Initialize(platformContext)) {
		// Functions in library
		static const luaL_Reg kFunctions[] = {
            {"init", init},
            {"isLoaded", isLoaded},
            {"show", show},
            {"load", load},
            {"getInfoForZone", getInfoForZone},
			{NULL, NULL}
        };

		// Register functions as closures, giving each access to the
		// 'library' instance via ToLibrary()
		{
			CoronaLuaPushUserdata(L, library, kMetatableName);
			luaL_openlib(L, kName, kFunctions, 1); // leave "library" on top of stack
		}
	}

	return 1;
}

int
AdColonyPlugin::Finalizer(lua_State *L)
{
    Self *library = (Self *)CoronaLuaToUserdata(L, 1);

    // Free the Lua listener
    CoronaLuaDeleteRef(L, adcolonyCoronaDelegate.coronaListener);
    adcolonyCoronaDelegate.coronaListener = NULL;
    
    // release all ad objects
    [adcolonyObjects removeAllObjects];
    adcolonyObjects = nil;
    
    adcolonyCoronaDelegate = nil;
    
	delete library;
		
	return 0;
}

AdColonyPlugin*
AdColonyPlugin::ToLibrary(lua_State *L)
{
	// library is pushed as part of the closure
	Self *library = (Self *)CoronaLuaToUserdata(L, lua_upvalueindex(1));
	return library;
}

AdColonyPlugin::AdColonyPlugin()
: coronaViewController(nil)
{
}

bool
AdColonyPlugin::Initialize(void *platformContext)
{
	bool shouldInit = (! coronaViewController);

	if (shouldInit) {
		id<CoronaRuntime> runtime = (__bridge id<CoronaRuntime>)platformContext;
		coronaViewController = runtime.appViewController;
        coronaWindow = runtime.appWindow;
        functionSignature = @"";
        
        // initial delegate
        adcolonyCoronaDelegate = [AdColonyCoronaDelegate new];
        adcolonyCoronaDelegate.coronaRuntime = runtime;
        
        // initialize ad object dictionary
        adcolonyObjects = [NSMutableDictionary new];
        
        // set default values
        adcolonyObjects[SDK_READY_KEY] = @(false);
	}

	return shouldInit;
}

// [Lua] init(listener, options)
int
AdColonyPlugin::init( lua_State *L )
{
    functionSignature = @"adcolony.init(listener, options)";

    // prevent init from being called more than once
    if (adcolonyCoronaDelegate.coronaListener != NULL) {
        logMsg(L, WARNING_MSG, @"init() should only be called once");
        return 0;
    }
    
    // get number of arguments
    int nargs = lua_gettop(L);
    if (nargs != 2) {
        logMsg(L, ERROR_MSG, MsgFormat(@"Expected 2 arguments, got %d", nargs));
        return 0;
    }
    
    const char *appId = NULL;
    const char *userId = NULL;
    const char *adOrientation = LANDSCAPE;
    bool debugLogging = false;
    NSDictionary *zoneTable = nil;
    NSNumber *hasUserConsent = nil;
    NSMutableDictionary<NSString*, NSNumber*>* privacyFrameworks = [NSMutableDictionary dictionaryWithCapacity:3];
    NSMutableDictionary<NSString*, NSString*>* privacyConsents = [NSMutableDictionary dictionaryWithCapacity:3];
    
    // Get listener key (required)
    if (CoronaLuaIsListener(L, 1, PROVIDER_NAME)) {
        adcolonyCoronaDelegate.coronaListener = CoronaLuaNewRef(L, 1);
    }
    else {
        logMsg(L, ERROR_MSG, MsgFormat(@"listener expected, got: %s", luaL_typename(L, 1)));
        return 0;
    }

    // check for options table (required)
    if (lua_type(L, 2) == LUA_TTABLE) {
        // traverse and verify all options
        for (lua_pushnil(L); lua_next(L, 2) != 0; lua_pop(L, 1)) {
            const char *key = lua_tostring(L, -2);
            
            if (UTF8IsEqual(key, "appId")) {
                if (lua_type(L, -1) == LUA_TSTRING) {
                    appId = lua_tostring(L, -1);
                }
                else {
                    logMsg(L, ERROR_MSG, MsgFormat(@"options.appId (string) expected, got: %s", luaL_typename(L, -1)));
                    return 0;
                }
            }
            else if (UTF8IsEqual(key, "adZones")) {
                if (lua_type(L, -1) == LUA_TTABLE) {
                    // we need gettop() here since -1 will return nil
                    zoneTable = CoronaLuaCreateDictionary(L, lua_gettop(L));
                }
                else {
                    logMsg(L, ERROR_MSG, MsgFormat(@"options.adZones (table) expected, got: %s", luaL_typename(L, -1)));
                    return 0;
                }
            }
            else if (UTF8IsEqual(key, "adOrientation")) {
                if (lua_type(L, -1) == LUA_TSTRING) {
                    adOrientation = lua_tostring(L, -1);
                }
                else {
                    logMsg(L, ERROR_MSG, MsgFormat(@"options.adOrientation (string) expected, got: %s", luaL_typename(L, -1)));
                    return 0;
                }
            }
            else if (UTF8IsEqual(key, "userId")) {
                if (lua_type(L, -1) == LUA_TSTRING) {
                    userId = lua_tostring(L, -1);
                }
                else {
                    logMsg(L, ERROR_MSG, MsgFormat(@"options.userId (string) expected, got: %s", luaL_typename(L, -1)));
                    return 0;
                }
            }
            else if (UTF8IsEqual(key, "debugLogging")) {
                if (lua_type(L, -1) == LUA_TBOOLEAN) {
                    debugLogging = lua_toboolean(L, -1);
                }
                else {
                    logMsg(L, ERROR_MSG, MsgFormat(@"options.debugLogging (boolean) expected, got: %s", luaL_typename(L, -1)));
                    return 0;
                }
            }
            else if (UTF8IsEqual(key, "privacyFrameworks")) {
				if (lua_istable(L, -1)) {
					int top = lua_gettop(L);
					for (lua_pushnil(L); lua_next(L, top) != 0; lua_pop(L, 1)) {
						if(lua_type(L, -2) == LUA_TSTRING) {
							NSString *consentType = [NSString stringWithUTF8String:lua_tostring(L, -2)];
							NSNumber *consentValue = [NSNumber numberWithBool:lua_toboolean(L, -1)];
							if ([@"gdpr" caseInsensitiveCompare:consentType] == NSOrderedSame) {
								[privacyFrameworks setObject:consentValue forKey:ADC_GDPR];
							} else if ([@"coppa" caseInsensitiveCompare:consentType] == NSOrderedSame) {
								[privacyFrameworks setObject:consentValue forKey:ADC_COPPA];
							} else if ([@"ccpa" caseInsensitiveCompare:consentType] == NSOrderedSame) {
								[privacyFrameworks setObject:consentValue forKey:ADC_CCPA];
							}
						}
					}
				} else {
					logMsg(L, ERROR_MSG, MsgFormat(@"options.privacyFrameworks (boolean) expected, got: %s", luaL_typename(L, -1)));
					return 0;
				}
			}
			else if (UTF8IsEqual(key, "privacyConsents")) {
				if (lua_istable(L, -1)) {
					int top = lua_gettop(L);
					for (lua_pushnil(L); lua_next(L, top) != 0; lua_pop(L, 1)) {
						if(lua_type(L, -2) == LUA_TSTRING) {
							NSString *consentType = [NSString stringWithUTF8String:lua_tostring(L, -2)];
							NSString *consentValue = lua_toboolean(L, -1)?@"1":@"0";
							if ([@"gdpr" caseInsensitiveCompare:consentType] == NSOrderedSame) {
								[privacyConsents setObject:consentValue forKey:ADC_GDPR];
							} else if ([@"coppa" caseInsensitiveCompare:consentType] == NSOrderedSame) {
								[privacyConsents setObject:consentValue forKey:ADC_COPPA];
							} else if ([@"ccpa" caseInsensitiveCompare:consentType] == NSOrderedSame) {
								[privacyConsents setObject:consentValue forKey:ADC_CCPA];
							}
						}
					}
				} else {
					logMsg(L, ERROR_MSG, MsgFormat(@"options.privacyFrameworks (boolean) expected, got: %s", luaL_typename(L, -1)));
					return 0;
				}
			}
            else if (UTF8IsEqual(key, "hasUserConsent")) {
                if (lua_type(L, -1) == LUA_TBOOLEAN) {
					logMsg(L, ERROR_MSG, @"options.hasUserConsent is deprecated. Please use privacyConsents");
                    hasUserConsent = [NSNumber numberWithBool:lua_toboolean(L, -1)];
                }
                else {
                    logMsg(L, ERROR_MSG, MsgFormat(@"options.hasUserConsent (boolean) expected, got: %s", luaL_typename(L, -1)));
                    return 0;
                    }
                } else {
                logMsg(L, ERROR_MSG, MsgFormat(@"Invalid option '%s'", key));
                return 0;
            }
        }
    }
    else { // no options table
        logMsg(L, ERROR_MSG, MsgFormat(@"options table expected, got %s", luaL_typename(L, 2)));
        return 0;
    }
    
    // validate
    if (appId == NULL) {
        logMsg(L, ERROR_MSG, MsgFormat(@"options.appId required"));
        return 0;
    }
    
    if (zoneTable == nil) {
        logMsg(L, ERROR_MSG, MsgFormat(@"options.adZones required"));
        return 0;
    }
    
    if (! UTF8IsEqual(adOrientation, PORTRAIT) && ! UTF8IsEqual(adOrientation, LANDSCAPE)) {
        logMsg(L, ERROR_MSG, MsgFormat(@"options.adOrientation. Invalid orientation '%s'", adOrientation));
        return 0;
    }
    
    // generate zoneIdArray for initialization
    NSMutableArray *zoneIdArray = [NSMutableArray new];
    for (NSString *zoneName in zoneTable) {
        [zoneIdArray addObject:zoneTable[zoneName]];
    }
    
    // save values for future use
    adcolonyObjects[APPID_KEY] = @(appId);
    adcolonyObjects[ZONETABLE_KEY] = zoneTable;
    
    // initialize app options object
    AdColonyAppOptions *appOptions = [AdColonyAppOptions new];
    appOptions.adOrientation = UTF8IsEqual(adOrientation, LANDSCAPE) ? AdColonyOrientationLandscape : AdColonyOrientationPortrait;
    
    // set custom user id
    if (userId != NULL) {
        appOptions.userID = @(userId);
    }
    
    // should we have debug logging?
    // (using negation since the AdColony API is a 'disable' flag and the plugin API is an 'enable' flag)
    appOptions.disableLogging = ! debugLogging;

    if (hasUserConsent != nil && ![privacyConsents objectForKey:ADC_GDPR]) {
        [privacyConsents setObject:[hasUserConsent boolValue]?@"1":@"0" forKey:ADC_GDPR];
    }
	for (NSString* consentType in privacyConsents) {
		if(![privacyFrameworks objectForKey:consentType]) {
			[privacyFrameworks setObject:[NSNumber numberWithBool:YES] forKey:consentType];
		}
	}
	
	for (NSString* consentType in privacyFrameworks) {
		[appOptions setPrivacyFrameworkOfType:consentType isRequired:[privacyFrameworks[consentType] boolValue]];
	}
	for (NSString* consentType in privacyConsents) {
		[appOptions setPrivacyConsentString:privacyConsents[consentType] forType:consentType];
	}
    
    // initialize the SDK
    [AdColony
        configureWithAppID: @(appId)
        zoneIDs: zoneIdArray
        options: appOptions
        completion: ^(NSArray<AdColonyZone*> *zones) {
            NSMutableDictionary *zoneStatus = [NSMutableDictionary new];

            for (AdColonyZone *zone in zones) {
                NSString *zoneType = TYPE_INTERSTITIAL;
                NSString *zoneId = [NSString stringWithString:zone.identifier];

                // configure rewarded block
                if (zone.rewarded)  {
                    zoneType = TYPE_REWARDEDVIDEO;
                    zone.reward = ^(BOOL success, NSString *name, int amount) {
                        [adcolonyCoronaDelegate onAdColonyReward:success currencyName:name currencyAmount:amount inZone:zoneId];
                    };
                }
                
                // get the zone name
                NSString *zoneName = nil;
                for (zoneName in zoneTable) {
                    if ([zoneId isEqualToString:zoneTable[zoneName]]) {
                        break;
                    }
                }
                
                // configure zone status (used in delegate callbacks)
                zoneStatus[zoneId] = [@{
                    ZONE_TYPE_KEY: zoneType,
                    ZONE_NAME_KEY: zoneName,
                    ZONE_LOADED_KEY: @(false)
                } mutableCopy];
            }

            // save values for future use
            adcolonyObjects[ZONESTATUS_KEY] = zoneStatus;

            // flag sdk as ready
            adcolonyObjects[SDK_READY_KEY] = @(true);

            // send Corona Lua event
            NSDictionary *coronaEvent = @{
                @(CoronaEventPhaseKey()) : PHASE_INIT
            };
            [adcolonyCoronaDelegate dispatchLuaEvent:coronaEvent];
        }
     ];
    
    // log plugin version to console
    NSLog(@"%s: %s (SDK: %@)", PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_SDK_VERSION);

    return 0;
}

// [Lua] isLoaded(zoneName)
int
AdColonyPlugin::isLoaded(lua_State *L)
{
    functionSignature = @"adcolony.isLoaded(zoneName)";
    
    // don't continue if SDK isn't initialized
    if (! isSDKInitialized(L)) {
        return 0;
    }
    
    // get number of arguments
    int nargs = lua_gettop(L);
    if (nargs != 1) {
        logMsg(L, ERROR_MSG, MsgFormat(@"1 argument expected, got %d", nargs));
        return 0;
    }
    
    const char *zoneName = NULL;
    
    // get zone name
    if (lua_type(L, 1) == LUA_TSTRING) {
        zoneName = lua_tostring(L, 1);
    }
    else {
        logMsg(L, ERROR_MSG, MsgFormat(@"zoneName (string) expected, got %s", luaL_typename(L, 1)));
        return 0;
    }
    
    // check if zone is ready to show ad
    NSString *zoneId = adcolonyObjects[ZONETABLE_KEY][@(zoneName)];

    if (zoneId == nil) {
        logMsg(L, ERROR_MSG, MsgFormat(@"zoneName '%s' doesn't exist", zoneName));
        return 0;
    }

    NSMutableDictionary *zoneStatus = adcolonyObjects[ZONESTATUS_KEY][zoneId];
    
    // check if ad is available
    AdColonyInterstitial *ad = zoneStatus[ZONE_ADOBJECT_KEY];
    bool isLoaded = ((ad != nil) && (! ad.expired) && [zoneStatus[ZONE_LOADED_KEY] boolValue]) ? true : false;

    lua_pushboolean(L, isLoaded);
    
    return 1;
}

// [Lua] show(zoneName)
int
AdColonyPlugin::show(lua_State *L)
{
    Self *context = ToLibrary(L);
    
    if (! context) { // abort if no valid context
        return 0;
    }
    
    Self& library = *context;

    functionSignature = @"adcolony.show(zoneName)";
    
    // don't continue if SDK isn't initialized
    if (! isSDKInitialized(L)) {
        return 0;
    }
    
    // get number of arguments
    int nargs = lua_gettop(L);
    if (nargs != 1) {
        logMsg(L, ERROR_MSG, MsgFormat(@"Expected 1 argument, got %d", nargs));
        return 0;
    }

    const char *zoneName = NULL;
    
    // get zone name
    if (lua_type(L, 1) == LUA_TSTRING) {
        zoneName = lua_tostring(L, 1);
    }
    else {
        logMsg(L, ERROR_MSG, MsgFormat(@"zoneName (string) expected, got %s", luaL_typename(L, 1)));
        return 0;
    }
    
    // check if zone is ready to show ad
    NSString *zoneId = adcolonyObjects[ZONETABLE_KEY][@(zoneName)];

    if (zoneId == nil) {
        logMsg(L, ERROR_MSG, MsgFormat(@"zoneName '%s' doesn't exist", zoneName));
        return 0;
    }

    NSMutableDictionary *zoneStatus = adcolonyObjects[ZONESTATUS_KEY][zoneId];
    
    // check if ad is available
    AdColonyInterstitial *ad = zoneStatus[ZONE_ADOBJECT_KEY];
    bool isLoaded = ((ad != nil) && (! ad.expired) && [zoneStatus[ZONE_LOADED_KEY] boolValue]) ? true : false;
    
    if (isLoaded) {
        [ad showWithPresentingViewController:library.coronaViewController];
    }
    else {
        logMsg(L, WARNING_MSG, MsgFormat(@"No ad available for zone '%s'", zoneName));
    }
    
    return 0;
}

// [Lua] load(zoneName [, options])
int
AdColonyPlugin::load(lua_State *L)
{
    functionSignature = @"adcolony.load(zoneName [, options])";
    
    // don't continue if SDK isn't initialized
    if (! isSDKInitialized(L)) {
        return 0;
    }
    
    // get number of arguments
    int nargs = lua_gettop(L);
    if ((nargs < 1) || (nargs > 2)) {
        logMsg(L, ERROR_MSG, MsgFormat(@"Expected 1 or 2 arguments, got %d", nargs));
        return 0;
    }
    
    const char *zoneName = NULL;
    bool prePopup = false;
    bool postPopup = false;
    
    // get zone name
    if (lua_type(L, 1) == LUA_TSTRING) {
        zoneName = lua_tostring(L, 1);
    }
    else {
        logMsg(L, ERROR_MSG, MsgFormat(@"zoneName (string) expected, got %s", luaL_typename(L, 1)));
        return 0;
    }
    
    // check for options table (optional)
    if (! lua_isnoneornil(L, 2)) {
        if (lua_type(L, 2) == LUA_TTABLE) {
            // traverse and verify all options
            for (lua_pushnil(L); lua_next(L, 2) != 0; lua_pop(L, 1)) {
                const char *key = lua_tostring(L, -2);
                
                if (UTF8IsEqual(key, "prePopup")) {
                    if (lua_type(L, -1) == LUA_TBOOLEAN) {
                        prePopup = lua_toboolean(L, -1);
                    }
                    else {
                        logMsg(L, ERROR_MSG, MsgFormat(@"options.prePopup (boolean) expected, got: %s", luaL_typename(L, -1)));
                        return 0;
                    }
                }
                else if (UTF8IsEqual(key, "postPopup")) {
                    if (lua_type(L, -1) == LUA_TBOOLEAN) {
                        postPopup = lua_toboolean(L, -1);
                    }
                    else {
                        logMsg(L, ERROR_MSG, MsgFormat(@"options.postPopup (boolean) expected, got: %s", luaL_typename(L, -1)));
                        return 0;
                    }
                }
                else {
                    logMsg(L, ERROR_MSG, MsgFormat(@"Invalid option '%s'", key));
                    return 0;
                }
            }
        }
        else { // no options table
            logMsg(L, ERROR_MSG, MsgFormat(@"options table expected, got %s", luaL_typename(L, 2)));
            return 0;
        }
    }
    
    // prepare zone to load an ad
    NSString *zoneId = adcolonyObjects[ZONETABLE_KEY][@(zoneName)];
    
    if (zoneId == nil) {
        logMsg(L, ERROR_MSG, MsgFormat(@"zoneName '%s' doesn't exist", zoneName));
        return 0;
    }
    
    // configure options
    AdColonyAdOptions *adOptions = [AdColonyAdOptions new];
    adOptions.showPrePopup = prePopup;
    adOptions.showPostPopup = postPopup;
    AdColonyInterstitialDel * interstitialDel = [AdColonyInterstitialDel alloc];
    interstitialDel.zoneId = zoneId;
    
    [AdColony requestInterstitialInZone:zoneId options:adOptions andDelegate:interstitialDel];
    
    return 0;
}

// [Lua] getInfoForZone(zoneName)
int
AdColonyPlugin::getInfoForZone(lua_State *L)
{
    functionSignature = @"adcolony.getInfoForZone(zoneName)";
    
    // don't continue if SDK isn't initialized
    if (! isSDKInitialized(L)) {
        return 0;
    }
    
    // get number of arguments
    int nargs = lua_gettop(L);
    if (nargs != 1) {
        logMsg(L, ERROR_MSG, MsgFormat(@"Expected 1 argument, got %d", nargs));
        return 0;
    }
    
    const char *zoneName = NULL;
    
    // get zone id
    if (lua_type(L, 1) == LUA_TSTRING) {
        zoneName = lua_tostring(L, 1);
    }
    else {
        logMsg(L, ERROR_MSG, MsgFormat(@"zoneName (string) expected, got %s", luaL_typename(L, 1)));
        return 0;
    }
    
    NSString *zoneId = adcolonyObjects[ZONETABLE_KEY][@(zoneName)];

    if (zoneId == nil) {
        logMsg(L, ERROR_MSG, MsgFormat(@"zoneName '%s' doesn't exist", zoneName));
        return 0;
    }
    
    // get zone info
    AdColonyZone *zoneInfo = [AdColony zoneForID:zoneId];
    
    // prepare event data
    NSDictionary *dataDict = @{
        @"zoneName": @(zoneName),
        @"isRewardedZone": @(zoneInfo.rewarded),
        @"virtualCurrencyName": zoneInfo.rewardName,
        @"rewardAmount": @(zoneInfo.rewardAmount),
        @"viewsPerReward": @(zoneInfo.viewsPerReward),
        @"viewsUntilReward": @(zoneInfo.viewsUntilReward)
    };
    
    // convert data to json
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:dataDict options:0 error:nil];
    NSMutableDictionary *zoneStatus = adcolonyObjects[ZONESTATUS_KEY][zoneId];
    
    // send Corona Lua event
    NSDictionary *coronaEvent = @{
        @(CoronaEventPhaseKey()) : PHASE_INFO,
        @(CoronaEventTypeKey()) : zoneStatus[ZONE_TYPE_KEY],
        CORONA_EVENT_DATA_KEY : [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding]
    };
    [adcolonyCoronaDelegate dispatchLuaEvent:coronaEvent];
    
    return 0;
}

// ----------------------------------------------------------------------------
// delegate implementation
// ----------------------------------------------------------------------------

@implementation AdColonyCoronaDelegate

// initializer
- (instancetype)init
{
    if (self = [super init]) {
        self.coronaListener = NULL;
        self.coronaRuntime = NULL;
    }
    
    return self;
}

// dispatch a new Lua event
- (void)dispatchLuaEvent:(NSDictionary *)dict
{
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        lua_State *L = self.coronaRuntime.L;
        CoronaLuaRef coronaListener = self.coronaListener;
        bool hasErrorKey = false;
        
        // create new event
        CoronaLuaNewEvent(L, EVENT_NAME);
        
        for (NSString *key in dict) {
            CoronaLuaPushValue(L, [dict valueForKey:key]);
            lua_setfield(L, -2, key.UTF8String);

            if (! hasErrorKey) {
                hasErrorKey = [key isEqualToString:@(CoronaEventIsErrorKey())];
            }
        }
        
        // add error key if not in dict
        if (! hasErrorKey) {
            lua_pushboolean(L, false);
            lua_setfield(L, -2, CoronaEventIsErrorKey());
        }
        
        // add provider
        lua_pushstring(L, PROVIDER_NAME );
        lua_setfield(L, -2, CoronaEventProviderKey());
        
        CoronaLuaDispatchEvent(L, coronaListener, 0);
    }];
}

// create JSON string
- (NSString *)getJSONStringForZone:(NSString *)zone currency:(NSString *)currency reward:(int)reward error:(AdColonyAdRequestError *)error
{
    NSMutableDictionary *dataDictionary = [NSMutableDictionary new];
    dataDictionary[@"zoneName"] = zone;
    
    if (reward != NO_DATA) {
        dataDictionary[@"reward"] = @(reward);
    }
    
    if (currency != nil) {
        dataDictionary[@"currencyName"] = currency;
    }
    
    if (error != nil) {
        dataDictionary[@"errorCode"] = @([error code]);
        dataDictionary[@"errorMsg"] = [error localizedDescription];
    }
    
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:dataDictionary options:0 error:nil];
    
    return [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
}

-(void)onAdColonyAdLoadedInZone:(NSString *)zoneID
{
    NSDictionary *zoneStatus = adcolonyObjects[ZONESTATUS_KEY][zoneID];
    
    // send Corona Lua event
    NSDictionary *coronaEvent = @{
        @(CoronaEventPhaseKey()) : PHASE_LOADED,
        @(CoronaEventTypeKey()) : zoneStatus[ZONE_TYPE_KEY],
        CORONA_EVENT_DATA_KEY : [self getJSONStringForZone:zoneStatus[ZONE_NAME_KEY] currency:nil reward:NO_DATA error:nil]
    };
    [self dispatchLuaEvent:coronaEvent];
    
}

-(void)onAdColonyAdFailedInZone:(NSString *)zoneID error:(AdColonyAdRequestError *)error
{
    NSDictionary *zoneStatus = adcolonyObjects[ZONESTATUS_KEY][zoneID];
    
    // send Corona Lua event
    NSDictionary *coronaEvent = @{
        @(CoronaEventPhaseKey()) : PHASE_FAILED,
        @(CoronaEventTypeKey()) : zoneStatus[ZONE_TYPE_KEY],
        CORONA_EVENT_DATA_KEY : [self getJSONStringForZone:zoneStatus[ZONE_NAME_KEY] currency:nil reward:NO_DATA error:error]
    };
    [self dispatchLuaEvent:coronaEvent];
}

-(void)onAdColonyReward:(BOOL)success currencyName:(NSString *)currencyName currencyAmount:(int)amount inZone:(NSString *)zoneID
{
    if (success) {
        NSDictionary *zoneStatus = adcolonyObjects[ZONESTATUS_KEY][zoneID];
        
        // send Corona Lua event
        NSDictionary *coronaEvent = @{
            @(CoronaEventPhaseKey()) : PHASE_REWARD,
            @(CoronaEventTypeKey()) : zoneStatus[ZONE_TYPE_KEY],
            CORONA_EVENT_DATA_KEY : [self getJSONStringForZone:zoneStatus[ZONE_NAME_KEY] currency:currencyName reward:amount error:nil]
        };
        [self dispatchLuaEvent:coronaEvent];
    }
}

-(void)onAdColonyAdStartedInZone:(NSString *)zoneID
{
    NSDictionary *zoneStatus = adcolonyObjects[ZONESTATUS_KEY][zoneID];
    
    // send Corona Lua event
    NSDictionary *coronaEvent = @{
        @(CoronaEventPhaseKey()) : PHASE_DISPLAYED,
        @(CoronaEventTypeKey()) : zoneStatus[ZONE_TYPE_KEY],
        CORONA_EVENT_DATA_KEY : [self getJSONStringForZone:zoneStatus[ZONE_NAME_KEY] currency:nil reward:NO_DATA error:nil]
    };
    [self dispatchLuaEvent:coronaEvent];

}

-(void)onAdColonyAdFinishedInZone:(NSString *)zoneID
{
    NSDictionary *zoneStatus = adcolonyObjects[ZONESTATUS_KEY][zoneID];
    
    // send Corona Lua event
    NSDictionary *coronaEvent = @{
        @(CoronaEventPhaseKey()) : PHASE_CLOSED,
        @(CoronaEventTypeKey()) : zoneStatus[ZONE_TYPE_KEY],
        CORONA_EVENT_DATA_KEY : [self getJSONStringForZone:zoneStatus[ZONE_NAME_KEY] currency:nil reward:NO_DATA error:nil]
    };
    [self dispatchLuaEvent:coronaEvent];
}

-(void)onAdColonyAdClickedInZone:(NSString *)zoneID
{
    NSDictionary *zoneStatus = adcolonyObjects[ZONESTATUS_KEY][zoneID];
    
    // send Corona Lua event
    NSDictionary *coronaEvent = @{
        @(CoronaEventPhaseKey()) : PHASE_CLICKED,
        @(CoronaEventTypeKey()) : zoneStatus[ZONE_TYPE_KEY],
        CORONA_EVENT_DATA_KEY : [self getJSONStringForZone:zoneStatus[ZONE_NAME_KEY] currency:nil reward:NO_DATA error:nil]
    };
    [self dispatchLuaEvent:coronaEvent];
}

-(void)onAdColonyAdExpiredInZone:(NSString *)zoneID
{
    NSDictionary *zoneStatus = adcolonyObjects[ZONESTATUS_KEY][zoneID];
    
    // send Corona Lua event
    NSDictionary *coronaEvent = @{
        @(CoronaEventPhaseKey()) : PHASE_EXPIRED,
        @(CoronaEventTypeKey()) : zoneStatus[ZONE_TYPE_KEY],
        CORONA_EVENT_DATA_KEY : [self getJSONStringForZone:zoneStatus[ZONE_NAME_KEY] currency:nil reward:NO_DATA error:nil]
    };
    [self dispatchLuaEvent:coronaEvent];
}


@end

@implementation AdColonyInterstitialDel
#pragma mark - AdColony Interstitial Delegate

// Store a reference to the returned interstitial object
- (void)adColonyInterstitialDidLoad:(AdColonyInterstitial *)interstitial {
    NSMutableDictionary *zoneStatus = adcolonyObjects[ZONESTATUS_KEY][self.zoneId];
    zoneStatus[ZONE_ADOBJECT_KEY] = interstitial; // save ad object instance
    zoneStatus[ZONE_LOADED_KEY] = @(true);
    [adcolonyCoronaDelegate onAdColonyAdLoadedInZone:self.zoneId];
}

// Handle loading error
- (void)adColonyInterstitialDidFailToLoad:(AdColonyAdRequestError *)error {
    NSMutableDictionary *zoneStatus = adcolonyObjects[ZONESTATUS_KEY][self.zoneId];
    zoneStatus[ZONE_ADOBJECT_KEY] = nil; // remove ad object instance
    zoneStatus[ZONE_LOADED_KEY] = @(false);
    
    [adcolonyCoronaDelegate onAdColonyAdFailedInZone:self.zoneId error:error];
}

// Handle expiring ads (optional)
- (void)adColonyInterstitialExpired:(AdColonyInterstitial *)interstitial  {
    NSMutableDictionary *zoneStatus = adcolonyObjects[ZONESTATUS_KEY][self.zoneId];
    zoneStatus[ZONE_ADOBJECT_KEY] = nil; // remove ad object instance
    zoneStatus[ZONE_LOADED_KEY] = @(false);
    [adcolonyCoronaDelegate onAdColonyAdExpiredInZone:self.zoneId];
    
}
- (void)adColonyInterstitialWillOpen:(AdColonyInterstitial *)interstitial {
    NSMutableDictionary *zoneStatus = adcolonyObjects[ZONESTATUS_KEY][self.zoneId];
    zoneStatus[ZONE_LOADED_KEY] = @(false);
    [adcolonyCoronaDelegate onAdColonyAdStartedInZone:self.zoneId];
}

- (void)adColonyInterstitialDidClose:(AdColonyInterstitial *)interstitial {
    [adcolonyCoronaDelegate onAdColonyAdFinishedInZone:self.zoneId];
}

- (void)adColonyInterstitialWillLeaveApplication:(AdColonyInterstitial *)interstitial {
    //Not Handled
}

- (void)adColonyInterstitialDidReceiveClick:(AdColonyInterstitial *)interstitial {
    [adcolonyCoronaDelegate onAdColonyAdClickedInZone:self.zoneId];
}
@end

// ----------------------------------------------------------------------------

CORONA_EXPORT int luaopen_plugin_adcolony( lua_State *L )
{
    return AdColonyPlugin::Open( L );
}
