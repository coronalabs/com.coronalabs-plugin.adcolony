//
// LuaLoader.java
// AdColony Plugin
//
// Copyright (c) 2016 CoronaLabs inc. All rights reserved.

// @formatter:off

package plugin.adcolony;

import com.naef.jnlua.LuaType;
import com.naef.jnlua.NamedJavaFunction;
import com.naef.jnlua.LuaState;
import com.naef.jnlua.JavaFunction;

import com.ansca.corona.CoronaEnvironment;
import com.ansca.corona.CoronaRuntime;
import com.ansca.corona.CoronaRuntimeListener;
import com.ansca.corona.CoronaActivity;
import com.ansca.corona.CoronaLua;
import com.ansca.corona.CoronaLuaEvent;
import com.ansca.corona.CoronaRuntimeTask;
import com.ansca.corona.CoronaRuntimeTaskDispatcher;

import java.util.HashMap;
import java.util.Hashtable;
import java.util.Map;

import android.util.Log;

import org.json.JSONObject;

// AdColony SDK imports
import com.adcolony.sdk.*;

/**
 * Implements the Lua interface for the AdColony Plugin.
 * <p/>
 * Only one instance of this class will be created by Corona for the lifetime of the application.
 * This instance will be re-used for every new Corona activity that gets created.
 */
@SuppressWarnings({"unused", "RedundantSuppression"})
public class LuaLoader implements JavaFunction, CoronaRuntimeListener {
    private static final String PLUGIN_NAME = "plugin.adcolony";
    private static final String PLUGIN_VERSION = "2.2.0";
    private static final String PLUGIN_SDK_VERSION = AdColony.getSDKVersion();

    private static final String EVENT_NAME = "adsRequest";
    private static final String PROVIDER_NAME = "adcolony";

    // event phases
    private static final String PHASE_INIT = "init";
    private static final String PHASE_INFO = "info";
    private static final String PHASE_LOADED = "loaded";
    private static final String PHASE_FAILED = "failed";
    private static final String PHASE_CLICKED = "clicked";
    private static final String PHASE_DISPLAYED = "displayed";
    private static final String PHASE_CLOSED = "closed";
    private static final String PHASE_EXPIRED = "expired";
    private static final String PHASE_REWARD = "reward";

    // response keys
    private static final String RESPONSE_LOADFAILED = "loadFailed";

    // Corona APP ID / SIG
    private static final String APPID_KEY = "appId";
    private static final String ZONETABLE_KEY = "zoneTable";
    private static final String ZONESTATUS_KEY = "zoneStatus";

    // add missing keys
    private static final String EVENT_PHASE_KEY = "phase";
    private static final String EVENT_TYPE_KEY = "type";
    private static final String EVENT_DATA_KEY = "data";

    // data keys
    private static final String DATA_ZONE_NAME = "zoneName";
    private static final String DATA_CURRENCY_NAME = "currencyName";
    private static final String DATA_REWARD = "reward";

    // message constants
    private static final String CORONA_TAG = "Corona";
    private static final String ERROR_MSG = "ERROR: ";
    private static final String WARNING_MSG = "WARNING: ";

    // convenience variables
    private static int coronaListener = CoronaLua.REFNIL;
    private static CoronaRuntimeTaskDispatcher coronaRuntimeTaskDispatcher = null;
    private static String functionSignature = ""; // used in error reporting functions

    // ad object dictionary
    private static final Map<String, Object> adcolonyObjects = new HashMap<>(); // keep track of loaded ad objects

    // object dictionary keys
    private static final String SDK_READY_KEY = "sdkReady";

    // ad types
    private static final String TYPE_INTERSTITIAL = "interstitial";
    private static final String TYPE_REWARDEDVIDEO = "rewardedVideo";

    // valid orientations
    private static final String PORTRAIT = "portrait";
    private static final String LANDSCAPE = "landscape";

    private static class ZoneStatusInfo {
        String zoneName;
        boolean loaded;
        Object adObject;

        public ZoneStatusInfo(String zoneName) {
            this.zoneName = zoneName;
            this.loaded = false;
            this.adObject = null;
        }
    }

    // -------------------------------------------------------------------
    // Plugin lifecycle events
    // -------------------------------------------------------------------

    /**
     * <p/>
     * Note that a new LuaLoader instance will not be created for every CoronaActivity instance.
     * That is, only one instance of this class will be created for the lifetime of the
     * application process.
     * This gives a plugin the option to do operations in the background while the CoronaActivity
     * is destroyed.
     */
    @SuppressWarnings("unused")
    public LuaLoader() {
        // Set up this plugin to listen for Corona runtime events to be received by methods
        // onLoaded(), onStarted(), onSuspended(), onResumed(), and onExiting().
        CoronaEnvironment.addRuntimeListener(this);
    }

    /**
     * Called when this plugin is being loaded via the Lua require() function.
     * <p/>
     * Note that this method will be called every time a new CoronaActivity has been launched.
     * This means that you'll need to re-initialize this plugin here.
     * <p/>
     * Warning! This method is not called on the main UI thread.
     *
     * @param L Reference to the Lua state that the require() function was called from.
     * @return Returns the number of values that the require() function will return.
     * <p/>
     * Expected to return 1, the library that the require() function is loading.
     */
    @Override
    public int invoke(LuaState L) {
        // Register this plugin into Lua with the following functions.
        NamedJavaFunction[] luaFunctions = new NamedJavaFunction[]{
                new Init(),
                new Show(),
                new Load(),
                new IsLoaded(),
                new GetInfoForZone()
        };
        String libName = L.toString(1);
        L.register(libName, luaFunctions);

        // Returning 1 indicates that the Lua require() function will return the above Lua
        return 1;
    }

    /**
     * Called after the Corona runtime has been created and just before executing the "main.lua"
     * file.
     * <p/>
     * Warning! This method is not called on the main thread.
     *
     * @param runtime Reference to the CoronaRuntime object that has just been loaded/initialized.
     *                Provides a LuaState object that allows the application to extend the Lua API.
     */
    @Override
    public void onLoaded(CoronaRuntime runtime) {
        // Note that this method will not be called the first time a Corona activity has been
        // launched.
        // This is because this listener cannot be added to the CoronaEnvironment until after
        // this plugin has been required-in by Lua, which occurs after the onLoaded() event.
        // However, this method will be called when a 2nd Corona activity has been created.

        if (coronaRuntimeTaskDispatcher == null) {
            coronaRuntimeTaskDispatcher = new CoronaRuntimeTaskDispatcher(runtime);

            // set default values
            adcolonyObjects.put(SDK_READY_KEY, false);
        }
    }

    /**
     * Called just after the Corona runtime has executed the "main.lua" file.
     * <p/>
     * Warning! This method is not called on the main thread.
     *
     * @param runtime Reference to the CoronaRuntime object that has just been started.
     */
    @Override
    public void onStarted(CoronaRuntime runtime) {
    }

    /**
     * Called just after the Corona runtime has been suspended which pauses all rendering, audio,
     * timers,
     * and other Corona related operations. This can happen when another Android activity (ie:
     * window) has
     * been displayed, when the screen has been powered off, or when the screen lock is shown.
     * <p/>
     * Warning! This method is not called on the main thread.
     *
     * @param runtime Reference to the CoronaRuntime object that has just been suspended.
     */
    @Override
    public void onSuspended(CoronaRuntime runtime) {
    }

    /**
     * Called just after the Corona runtime has been resumed after a suspend.
     * <p/>
     * Warning! This method is not called on the main thread.
     *
     * @param runtime Reference to the CoronaRuntime object that has just been resumed.
     */
    @Override
    public void onResumed(CoronaRuntime runtime) {
    }

    /**
     * Called just before the Corona runtime terminates.
     * <p/>
     * This happens when the Corona activity is being destroyed which happens when the user
     * presses the Back button
     * on the activity, when the native.requestExit() method is called in Lua, or when the
     * activity's finish()
     * method is called. This does not mean that the application is exiting.
     * <p/>
     * Warning! This method is not called on the main thread.
     *
     * @param runtime Reference to the CoronaRuntime object that is being terminated.
     */
    @Override
    public void onExiting(CoronaRuntime runtime) {
        if (adcolonyObjects.get(SDK_READY_KEY) != null) {
            if ((boolean) adcolonyObjects.get(SDK_READY_KEY)) {
                // release listeners
                AdColony.removeRewardListener();
                Hashtable<String, String> zoneTable = (Hashtable) adcolonyObjects.get(ZONETABLE_KEY);
                for (String zoneName : zoneTable.keySet()) {
                    String zoneId = zoneTable.get(zoneName);
                    ZoneStatusInfo zoneStatus = (ZoneStatusInfo) ((HashMap) adcolonyObjects.get(ZONESTATUS_KEY)).get(zoneId);
                    AdColonyInterstitial interstitial = (AdColonyInterstitial) zoneStatus.adObject;
                    if (interstitial != null) {
                        interstitial.setListener(null);
                    }
                }
            }
        }

        // release references
        CoronaLua.deleteRef(runtime.getLuaState(), coronaListener);
        coronaListener = CoronaLua.REFNIL;
        coronaRuntimeTaskDispatcher = null;

        // release all objects
        adcolonyObjects.clear();
    }

    // -------------------------------------------------------------------
    // helper functions
    // -------------------------------------------------------------------

    // log message to console
    private void logMsg(String msgType, String errorMsg) {
        String functionID = functionSignature;
        if (!functionID.isEmpty()) {
            functionID += ", ";
        }

        Log.i(CORONA_TAG, msgType + functionID + errorMsg);
    }

    // return true if SDK is properly initialized
    private boolean isSDKInitialized() {
        if (coronaListener == CoronaLua.REFNIL) {
            logMsg(ERROR_MSG, "adcolony.init() must be called before calling other API functions");
            return false;
        }

        if (!(boolean) adcolonyObjects.get(SDK_READY_KEY)) {
            logMsg(ERROR_MSG, "Please wait for the 'init' event before calling other API functions");
            return false;
        }

        return true;
    }

    // dispatch a Lua event to our callback (dynamic handling of properties through map)
    private void dispatchLuaEvent(final Map<String, Object> event) {
        if (coronaRuntimeTaskDispatcher != null) {
            coronaRuntimeTaskDispatcher.send(new CoronaRuntimeTask() {
                @Override
                public void executeUsing(CoronaRuntime runtime) {
                    try {
                        LuaState L = runtime.getLuaState();
                        CoronaLua.newEvent(L, EVENT_NAME);
                        boolean hasErrorKey = false;

                        // add event parameters from map
                        for (String key : event.keySet()) {
                            CoronaLua.pushValue(L, event.get(key));           // push value
                            L.setField(-2, key);                              // push key

                            if (!hasErrorKey) {
                                hasErrorKey = key.equals(CoronaLuaEvent.ISERROR_KEY);
                            }
                        }

                        // add error key if not in map
                        if (!hasErrorKey) {
                            L.pushBoolean(false);
                            L.setField(-2, CoronaLuaEvent.ISERROR_KEY);
                        }

                        // add provider
                        L.pushString(PROVIDER_NAME);
                        L.setField(-2, CoronaLuaEvent.PROVIDER_KEY);

                        CoronaLua.dispatchEvent(L, coronaListener, 0);
                    } catch (Exception ex) {
                        ex.printStackTrace();
                    }
                }
            });
        }
    }

    // -------------------------------------------------------------------
    // Plugin implementation
    // -------------------------------------------------------------------

    // [Lua] init(listener, options)
    private class Init implements NamedJavaFunction {
        @Override
        public String getName() {
            return "init";
        }

        @Override
        public int invoke(LuaState luaState) {
            functionSignature = "adcolony.init(listener, options)";

            // prevent init from being called more than once
            if (coronaListener != CoronaLua.REFNIL) {
                logMsg(WARNING_MSG, "init() should only be called once");
                return 0;
            }

            // get number of arguments
            int nargs = luaState.getTop();
            if (nargs != 2) {
                logMsg(ERROR_MSG, "Expected 2 arguments, got " + nargs);
                return 0;
            }

            String appId = null;
            String userId = null;
            String adOrientation = null;
            boolean debugLogging = false;
            Hashtable<String, String> zoneTable = null;
            Boolean hasUserConsent = null;
            final HashMap<String, String> privacyConsents = new HashMap<>();
            final HashMap<String, Boolean> privacyFrameworks = new HashMap<>();

            // Get listener key (required)
            if (CoronaLua.isListener(luaState, 1, PROVIDER_NAME)) {
                coronaListener = CoronaLua.newRef(luaState, 1);
            } else {
                logMsg(ERROR_MSG, "listener expected, got: " + luaState.typeName(1));
                return 0;
            }

            // check for options table (required)
            if (luaState.type(2) == LuaType.TABLE) {
                // traverse and verify all options
                for (luaState.pushNil(); luaState.next(2); luaState.pop(1)) {
                    String key = luaState.toString(-2);

                    if (key.equals("appId")) {
                        if (luaState.type(-1) == LuaType.STRING) {
                            appId = luaState.toString(-1);
                        } else {
                            logMsg(ERROR_MSG, "options.appId (string) expected, got: " + luaState.typeName(-1));
                            return 0;
                        }
                    } else if (key.equals("adZones")) {
                        if (luaState.type(-1) == LuaType.TABLE) {
                            zoneTable = (Hashtable) CoronaLua.toHashtable(luaState, -1);
                        } else {
                            logMsg(ERROR_MSG, "options.adZones (table) expected, got: " + luaState.typeName(-1));
                            return 0;
                        }
                    } else if (key.equals("adOrientation")) {
                        if (luaState.type(-1) == LuaType.STRING) {
                            adOrientation = luaState.toString(-1);
                        } else {
                            logMsg(ERROR_MSG, "options.adOrientation (string) expected, got: " + luaState.typeName(-1));
                            return 0;
                        }
                    } else if (key.equals("userId")) {
                        if (luaState.type(-1) == LuaType.STRING) {
                            userId = luaState.toString(-1);
                        } else {
                            logMsg(ERROR_MSG, "options.userId (string) expected, got: " + luaState.typeName(-1));
                            return 0;
                        }
                    } else if (key.equals("debugLogging")) {
                        if (luaState.type(-1) == LuaType.BOOLEAN) {
                            debugLogging = luaState.toBoolean(-1);
                        } else {
                            logMsg(ERROR_MSG, "options.debugLogging (boolean) expected, got: " + luaState.typeName(-1));
                            return 0;
                        }
                    } else if (key.equals("privacyFrameworks")) {
                        if (luaState.isTable(-1)) {
                            int top = luaState.getTop();
                            for (luaState.pushNil(); luaState.next(top); luaState.pop(1)) {
                                if(luaState.type(-2) == LuaType.STRING) {
                                    String consentType = luaState.toString(-2);
                                    boolean consentValue = luaState.toBoolean(-1);
                                    if (consentType.equalsIgnoreCase("gdpr")) {
                                        privacyFrameworks.put(AdColonyAppOptions.GDPR, consentValue);
                                    } else if (consentType.equalsIgnoreCase("coppa")) {
                                        privacyFrameworks.put(AdColonyAppOptions.COPPA, consentValue);
                                    } else if (consentType.equalsIgnoreCase("ccpa")) {
                                        privacyFrameworks.put(AdColonyAppOptions.CCPA, consentValue);
                                    }
                                }
                            }
                        } else {
                            logMsg(ERROR_MSG, "options.privacyFrameworks expected Table. Got " + luaState.typeName(-1));
                            return 0;
                        }
                    } else if (key.equals("privacyConsents")) {
                        if (luaState.isTable(-1)) {
                            int top = luaState.getTop();
                            for (luaState.pushNil(); luaState.next(top); luaState.pop(1)) {
                                if(luaState.type(-2) == LuaType.STRING) {
                                    String consentType = luaState.toString(-2);
                                    String consentValue = luaState.toBoolean(-1) ? "1" : "0";
                                    if (consentType.equalsIgnoreCase("gdpr")) {
                                        privacyConsents.put(AdColonyAppOptions.GDPR, consentValue);
                                    } else if (consentType.equalsIgnoreCase("coppa")) {
                                        privacyConsents.put(AdColonyAppOptions.COPPA, consentValue);
                                    } else if (consentType.equalsIgnoreCase("ccpa")) {
                                        privacyConsents.put(AdColonyAppOptions.CCPA, consentValue);
                                    }
                                }
                            }
                        } else {
                            logMsg(ERROR_MSG, "options.privacyConsents expected Table. Got " + luaState.typeName(-1));
                            return 0;
                        }
                    } else if (key.equals("hasUserConsent")) {
                        if (luaState.type(-1) == LuaType.BOOLEAN) {
                            logMsg(WARNING_MSG, "options.hasUserConsent is deprecated. Assuming GDPR");
                            hasUserConsent = luaState.toBoolean(-1);
                        } else {
                            logMsg(ERROR_MSG, "options.hasUserConsent expected (boolean). Got " + luaState.typeName(-1));
                            return 0;
                        }
                    } else {
                        logMsg(ERROR_MSG, "Invalid option '" + key + "'");
                        return 0;
                    }
                }
            } else { // no options table
                logMsg(ERROR_MSG, "options table expected, got " + luaState.typeName(2));
                return 0;
            }

            if (hasUserConsent != null && !privacyConsents.containsKey(AdColonyAppOptions.GDPR)) {
                privacyConsents.put(AdColonyAppOptions.GDPR, hasUserConsent ? "1" : "0");
            }
            for (Map.Entry<String, String> entry : privacyConsents.entrySet()) {
                if (!privacyFrameworks.containsKey(entry.getKey())) {
                    privacyFrameworks.put(entry.getKey(), true);
                }
            }

            // validation
            if (appId == null) {
                logMsg(ERROR_MSG, "options.appId required");
                return 0;
            }

            if (zoneTable == null) {
                logMsg(ERROR_MSG, "options.adZones required");
                return 0;
            }

            if (adOrientation!=null && !adOrientation.equals(LANDSCAPE) && !adOrientation.equals(PORTRAIT)) {
                logMsg(ERROR_MSG, "options.adOrientation. Invalid orientation '" + adOrientation + "'");
                return 0;
            }

            // create zone id array for initialization
            String[] zoneIdArray = new String[zoneTable.size()];
            int i = 0;
            for (String zoneName : zoneTable.keySet()) {
                zoneIdArray[i++] = zoneTable.get(zoneName);
            }

            // save values for future use
            adcolonyObjects.put(APPID_KEY, appId);
            adcolonyObjects.put(ZONETABLE_KEY, zoneTable);

            // declare final variables for inner loop
            final CoronaActivity coronaActivity = CoronaEnvironment.getCoronaActivity();
            final String fAppId = appId;
            final String fUserId = userId;
            final String[] fZoneIdArray = zoneIdArray;
            final Hashtable<String, String> fZoneTable = zoneTable;
            final String fAdOrientation = adOrientation;

            // Run the activity on the uiThread
            if (coronaActivity != null) {
                Runnable runnableActivity = new Runnable() {
                    public void run() {
                        // Create a new runnable object to invoke our activity
                        Runnable runnableActivity = new Runnable() {
                            public void run() {
                                // configure app options
                                AdColonyAppOptions appOptions = new AdColonyAppOptions();
                                String targetStore = android.os.Build.MANUFACTURER.equals("Amazon") ? "amazon" : "google";
                                appOptions.setOriginStore(targetStore);
                                if(fAdOrientation!=null) {
                                    appOptions.setRequestedAdOrientation(fAdOrientation.equals(LANDSCAPE) ? AdColonyAppOptions.LANDSCAPE : AdColonyAppOptions.PORTRAIT);
                                }

                                // set custom user id
                                if (fUserId != null) {
                                    appOptions.setUserID(fUserId);
                                }

                                for (Map.Entry<String, Boolean> entry : privacyFrameworks.entrySet()) {
                                    appOptions.setPrivacyFrameworkRequired(entry.getKey(), entry.getValue());
                                }

                                for (Map.Entry<String, String> entry : privacyConsents.entrySet()) {
                                    appOptions.setPrivacyConsentString(entry.getKey(), entry.getValue());
                                }

                                // initialize the SDK
                                AdColony.configure(coronaActivity, appOptions, fAppId, fZoneIdArray);
                                AdColony.setRewardListener(new CoronaAdColonyRewardListener());

                                // log plugin version to console
                                Log.i(CORONA_TAG, PLUGIN_NAME + ": " + PLUGIN_VERSION + " (SDK: " + PLUGIN_SDK_VERSION + ")");

                                // configure zone status
                                HashMap<String, ZoneStatusInfo> zoneStatus = new HashMap<>();
                                for (String zoneName : fZoneTable.keySet()) {
                                    zoneStatus.put(fZoneTable.get(zoneName), new ZoneStatusInfo(zoneName));
                                }
                                adcolonyObjects.put(ZONESTATUS_KEY, zoneStatus);

                                // flag sdk as ready
                                adcolonyObjects.put(SDK_READY_KEY, true);

                                // send Corona Lua event
                                Map<String, Object> coronaEvent = new HashMap<>();
                                coronaEvent.put(EVENT_PHASE_KEY, PHASE_INIT);
                                dispatchLuaEvent(coronaEvent);
                            }
                        };

                        coronaActivity.runOnUiThread(runnableActivity);
                    }
                };

                coronaActivity.runOnUiThread(runnableActivity);
            }

            return 0;
        }
    }

    // [Lua] isLoaded(zoneName)
    @SuppressWarnings("unused")
    private class IsLoaded implements NamedJavaFunction {
        @Override
        public String getName() {
            return "isLoaded";
        }

        @Override
        public int invoke(LuaState luaState) {
            functionSignature = "adcolony.isLoaded(zoneName)";

            // don't continue if SDK isn't initialized
            if (!isSDKInitialized()) {
                return 0;
            }

            // get number of arguments
            int nargs = luaState.getTop();
            if (nargs != 1) {
                logMsg(ERROR_MSG, "1 argument expected, got " + nargs);
                return 0;
            }

            String zoneName = null;

            // get zone id
            if (luaState.type(1) == LuaType.STRING) {
                zoneName = luaState.toString(1);
            } else {
                logMsg(ERROR_MSG, "zoneName (string) expected, got " + luaState.typeName(1));
                return 0;
            }

            String zoneId = ((Hashtable<String, String>) adcolonyObjects.get(ZONETABLE_KEY)).get(zoneName);

            if (zoneId == null) {
                logMsg(ERROR_MSG, "zoneName '" + zoneName + "' doesn't exist");
                return 0;
            }

            ZoneStatusInfo zoneStatus = (ZoneStatusInfo) ((HashMap) adcolonyObjects.get(ZONESTATUS_KEY)).get(zoneId);
            AdColonyInterstitial interstitial = (AdColonyInterstitial) zoneStatus.adObject;
            boolean isLoaded = ((interstitial != null) && (!interstitial.isExpired()) && zoneStatus.loaded);

            luaState.pushBoolean(isLoaded);

            return 1;
        }
    }

    // [Lua] show(zoneName)
    @SuppressWarnings("unused")
    private class Show implements NamedJavaFunction {
        @Override
        public String getName() {
            return "show";
        }

        @Override
        public int invoke(LuaState luaState) {
            functionSignature = "adcolony.show(zoneName)";

            // don't continue if SDK isn't initialized
            if (!isSDKInitialized()) {
                return 0;
            }

            // get number of arguments
            int nargs = luaState.getTop();
            if (nargs != 1) {
                logMsg(ERROR_MSG, "Expected 1 argument, got " + nargs);
                return 0;
            }

            String zoneName = null;

            // get zone name
            if (luaState.type(1) == LuaType.STRING) {
                zoneName = luaState.toString(1);
            } else {
                logMsg(ERROR_MSG, "zoneName (string) expected, got " + luaState.typeName(1));
                return 0;
            }

            String zoneId = ((Hashtable<String, String>) adcolonyObjects.get(ZONETABLE_KEY)).get(zoneName);

            if (zoneId == null) {
                logMsg(ERROR_MSG, "zoneName '" + zoneName + "' doesn't exist");
                return 0;
            }

            ZoneStatusInfo zoneStatus = (ZoneStatusInfo) ((HashMap) adcolonyObjects.get(ZONESTATUS_KEY)).get(zoneId);

            // declare final vars for inner loop
            final CoronaActivity coronaActivity = CoronaEnvironment.getCoronaActivity();
            final AdColonyInterstitial interstitial = (AdColonyInterstitial) zoneStatus.adObject;
            final boolean isLoaded = ((interstitial != null) && (!interstitial.isExpired()) && zoneStatus.loaded);
            final String fZoneName = zoneName;

            if (!isLoaded) {
                logMsg(ERROR_MSG, "No ad available for zone '" + zoneName + "'");
                return 0;
            }

            if (coronaActivity != null) {
                coronaActivity.runOnUiThread(new Runnable() {
                    @Override
                    public void run() {
                        // send coronaOnOpened (see onOpened listener for details)
                        CoronaAdColonyInterstitialListener listener = (CoronaAdColonyInterstitialListener) interstitial.getListener();
                        listener.coronaOnOpened(interstitial);

                        interstitial.show();
                    }
                });
            }

            return 0;
        }
    }

    // [Lua] load(zoneName [, options])
    @SuppressWarnings("unused")
    private class Load implements NamedJavaFunction {
        @Override
        public String getName() {
            return "load";
        }

        @Override
        public int invoke(LuaState luaState) {
            functionSignature = "adcolony.load(zoneName [, options])";

            // don't continue if SDK isn't initialized
            if (!isSDKInitialized()) {
                return 0;
            }

            // get number of arguments
            int nargs = luaState.getTop();
            if ((nargs < 1) || (nargs > 2)) {
                logMsg(ERROR_MSG, "Expected 1 or 2 arguments, got " + nargs);
                return 0;
            }

            final String zoneName;
            boolean prePopup = false;
            boolean postPopup = false;

            // get zone name
            if (luaState.type(1) == LuaType.STRING) {
                zoneName = luaState.toString(1);
            } else {
                logMsg(ERROR_MSG, "zoneName (string) expected, got " + luaState.typeName(1));
                return 0;
            }

            // check for options table (optional)
            if (!luaState.isNoneOrNil(2)) {
                if (luaState.type(2) == LuaType.TABLE) {
                    // traverse and verify all options
                    for (luaState.pushNil(); luaState.next(2); luaState.pop(1)) {
                        String key = luaState.toString(-2);

                        if (key.equals("prePopup")) {
                            if (luaState.type(-1) == LuaType.BOOLEAN) {
                                prePopup = luaState.toBoolean(-1);
                            } else {
                                logMsg(ERROR_MSG, "options.prePopup (boolean) expected, got: " + luaState.typeName(-1));
                                return 0;
                            }
                        } else if (key.equals("postPopup")) {
                            if (luaState.type(-1) == LuaType.BOOLEAN) {
                                postPopup = luaState.toBoolean(-1);
                            } else {
                                logMsg(ERROR_MSG, "options.postPopup (boolean) expected, got: " + luaState.typeName(-1));
                                return 0;
                            }
                        } else {
                            logMsg(ERROR_MSG, "Invalid option ' " + key + "'");
                            return 0;
                        }
                    }
                } else { // no options table
                    logMsg(ERROR_MSG, "options table expected, got " + luaState.typeName(2));
                    return 0;
                }
            }

            // get zone config
            final String zoneId = ((Hashtable<String, String>) adcolonyObjects.get(ZONETABLE_KEY)).get(zoneName);
            if (zoneId == null) {
                logMsg(ERROR_MSG, "zoneName '" + zoneName + "' doesn't exist");
                return 0;
            }

            // declare final vars for inner loop
            final CoronaActivity coronaActivity = CoronaEnvironment.getCoronaActivity();
            final boolean fPrePopup = prePopup;
            final boolean fPostPopup = postPopup;

            if (coronaActivity != null) {
                Runnable runnableActivity = new Runnable() {
                    public void run() {
                        // set ad options
                        AdColonyAdOptions adOptions = new AdColonyAdOptions();
                        adOptions.enableConfirmationDialog(fPrePopup);
                        adOptions.enableResultsDialog(fPostPopup);

                        // load the ad
                        AdColony.requestInterstitial(zoneId, new CoronaAdColonyInterstitialListener(zoneName), adOptions);
                    }
                };

                coronaActivity.runOnUiThread(runnableActivity);
            }

            return 0;
        }
    }

    // [Lua] getInfoForZone(zoneName)
    @SuppressWarnings("unused")
    private class GetInfoForZone implements NamedJavaFunction {
        @Override
        public String getName() {
            return "getInfoForZone";
        }

        @Override
        public int invoke(LuaState luaState) {
            functionSignature = "adcolony.getInfoForZone(zoneName)";

            // don't continue if SDK isn't initialized
            if (!isSDKInitialized()) {
                return 0;
            }

            // get number of arguments
            int nargs = luaState.getTop();
            if (nargs != 1) {
                logMsg(ERROR_MSG, "1 argument expected, got " + nargs);
                return 0;
            }

            String zoneName = null;

            // get zone id
            if (luaState.type(1) == LuaType.STRING) {
                zoneName = luaState.toString(1);
            } else {
                logMsg(ERROR_MSG, "zoneName (string) expected, got " + luaState.typeName(1));
                return 0;
            }

            String zoneId = ((Hashtable<String, String>) adcolonyObjects.get(ZONETABLE_KEY)).get(zoneName);
            if (zoneId == null) {
                logMsg(ERROR_MSG, "zoneName '" + zoneName + "' doesn't exist");
                return 0;
            }

            AdColonyZone zoneInfo = AdColony.getZone(zoneId);

            // create data
            JSONObject data = new JSONObject();
            try {
                data.put("zoneName", zoneName);
                data.put("isRewardedZone", zoneInfo.isRewarded());
                data.put("virtualCurrencyName", zoneInfo.getRewardName());
                data.put("rewardAmount", zoneInfo.getRewardAmount());
                data.put("viewsPerReward", zoneInfo.getViewsPerReward());
                data.put("viewsUntilReward", zoneInfo.getRemainingViewsUntilReward());
            } catch (Exception e) {
                System.err.println();
            }

            // send Corona Lua event
            Map<String, Object> coronaEvent = new HashMap<>();
            coronaEvent.put(EVENT_PHASE_KEY, PHASE_INFO);
            coronaEvent.put(EVENT_TYPE_KEY, zoneInfo.isRewarded() ? TYPE_REWARDEDVIDEO : TYPE_INTERSTITIAL);
            coronaEvent.put(EVENT_DATA_KEY, data.toString());
            dispatchLuaEvent(coronaEvent);

            return 0;
        }
    }

    // -------------------------------------------------------------------
    // Delegates
    // -------------------------------------------------------------------

    private class CoronaAdColonyInterstitialListener extends AdColonyInterstitialListener {
        private String zoneName;

        CoronaAdColonyInterstitialListener(String zoneName) {
            this.zoneName = zoneName;
        }

        @Override
        public void onClicked(AdColonyInterstitial ad) {
            AdColonyZone zoneInfo = AdColony.getZone(ad.getZoneID());
            // create data
            JSONObject data = new JSONObject();
            try {
                data.put(DATA_ZONE_NAME, zoneName);
            } catch (Exception e) {
                System.err.println();
            }

            // send Corona Lua event
            Map<String, Object> coronaEvent = new HashMap<>();
            coronaEvent.put(EVENT_PHASE_KEY, PHASE_CLICKED);
            coronaEvent.put(EVENT_TYPE_KEY, zoneInfo.isRewarded() ? TYPE_REWARDEDVIDEO : TYPE_INTERSTITIAL);
            coronaEvent.put(EVENT_DATA_KEY, data.toString());
            dispatchLuaEvent(coronaEvent);

            super.onClicked(ad);
        }

        @Override
        public void onClosed(AdColonyInterstitial ad) {
            AdColonyZone zoneInfo = AdColony.getZone(ad.getZoneID());
            // create data
            JSONObject data = new JSONObject();
            try {
                data.put(DATA_ZONE_NAME, zoneName);
            } catch (Exception e) {
                System.err.println();
            }

            // send Corona Lua event
            Map<String, Object> coronaEvent = new HashMap<>();
            coronaEvent.put(EVENT_PHASE_KEY, PHASE_CLOSED);
            coronaEvent.put(EVENT_TYPE_KEY, zoneInfo.isRewarded() ? TYPE_REWARDEDVIDEO : TYPE_INTERSTITIAL);
            coronaEvent.put(EVENT_DATA_KEY, data.toString());
            dispatchLuaEvent(coronaEvent);
            super.onClosed(ad);
        }

        @Override
        public void onExpiring(AdColonyInterstitial ad) {
            ZoneStatusInfo zoneStatus = (ZoneStatusInfo) ((HashMap) adcolonyObjects.get(ZONESTATUS_KEY)).get(ad.getZoneID());

            if (zoneStatus != null) {

                // remove the ad
                zoneStatus.adObject = null;
                zoneStatus.loaded = false;
            }
            AdColonyZone zoneInfo = AdColony.getZone(ad.getZoneID());

            // create data
            JSONObject data = new JSONObject();
            try {
                data.put(DATA_ZONE_NAME, zoneName);
            } catch (Exception e) {
                System.err.println();
            }

            // send Corona Lua event
            Map<String, Object> coronaEvent = new HashMap<>();
            coronaEvent.put(EVENT_PHASE_KEY, PHASE_EXPIRED);
            coronaEvent.put(EVENT_TYPE_KEY, zoneInfo.isRewarded() ? TYPE_REWARDEDVIDEO : TYPE_INTERSTITIAL);
            coronaEvent.put(EVENT_DATA_KEY, data.toString());
            dispatchLuaEvent(coronaEvent);

            super.onExpiring(ad);
        }

        public void coronaOnOpened(AdColonyInterstitial ad) {
            if (!adcolonyObjects.isEmpty()) {
                ZoneStatusInfo zoneStatus = (ZoneStatusInfo) ((HashMap) adcolonyObjects.get(ZONESTATUS_KEY)).get(ad.getZoneID());

                if (zoneStatus != null) {
                    // flag ad as used
                    zoneStatus.loaded = false;
                }
            }

            AdColonyZone zoneInfo = AdColony.getZone(ad.getZoneID());

            // create data
            JSONObject data = new JSONObject();
            try {
                data.put(DATA_ZONE_NAME, zoneName);
            } catch (Exception e) {
                System.err.println();
            }

            // send Corona Lua event
            Map<String, Object> coronaEvent = new HashMap<>();
            coronaEvent.put(EVENT_PHASE_KEY, PHASE_DISPLAYED);
            coronaEvent.put(EVENT_TYPE_KEY, zoneInfo.isRewarded() ? TYPE_REWARDEDVIDEO : TYPE_INTERSTITIAL);
            coronaEvent.put(EVENT_DATA_KEY, data.toString());
            dispatchLuaEvent(coronaEvent);

            super.onOpened(ad);
        }

        @Override
        public void onOpened(AdColonyInterstitial ad) {
            // NOP
            // see coronaOnOpened()
            // Since the ad activity takes control before this event is processed by Lua, the plugin will
            // programmitically send coronaOnOpened() in show() instead
        }

        @Override
        public void onRequestFilled(AdColonyInterstitial ad) {
            if (!adcolonyObjects.isEmpty()) {
                String zoneID = ad.getZoneID();
                if (zoneID != null) {
                    HashMap zoneMap = (HashMap) adcolonyObjects.get(ZONESTATUS_KEY);
                    if (!zoneMap.isEmpty()) {
                        ZoneStatusInfo zoneStatus = (ZoneStatusInfo) zoneMap.get(zoneID);
                        if (zoneStatus != null) {

                            // save the ad
                            zoneStatus.adObject = ad;
                            zoneStatus.loaded = true;
                        }
                    }
                    AdColonyZone zoneInfo = AdColony.getZone(ad.getZoneID());

                    // create data
                    JSONObject data = new JSONObject();
                    try {
                        data.put(DATA_ZONE_NAME, zoneName);
                    } catch (Exception e) {
                        System.err.println();
                    }

                    // send Corona Lua event
                    Map<String, Object> coronaEvent = new HashMap<>();
                    coronaEvent.put(EVENT_PHASE_KEY, PHASE_LOADED);
                    coronaEvent.put(EVENT_TYPE_KEY, zoneInfo.isRewarded() ? TYPE_REWARDEDVIDEO : TYPE_INTERSTITIAL);
                    coronaEvent.put(EVENT_DATA_KEY, data.toString());
                    dispatchLuaEvent(coronaEvent);
                }
            }
        }

        @Override
        public void onRequestNotFilled(AdColonyZone zone) {
            if (zone != null) {
                String zoneID = zone.getZoneID();
                HashMap zoneStatusHashMap = (HashMap) adcolonyObjects.get(ZONESTATUS_KEY);
                if (zoneStatusHashMap != null && !zoneStatusHashMap.isEmpty()) {
                    ZoneStatusInfo zoneStatus = (ZoneStatusInfo) zoneStatusHashMap.get(zoneID);
                    if (zoneStatus != null) {
                        // remove the ad
                        zoneStatus.adObject = null;
                        zoneStatus.loaded = false;
                    }
                }

                // create data
                JSONObject data = new JSONObject();
                try {
                    data.put(DATA_ZONE_NAME, zoneName);
                } catch (Exception e) {
                    System.err.println();
                }

                // send Corona Lua event
                Map<String, Object> coronaEvent = new HashMap<>();
                coronaEvent.put(EVENT_PHASE_KEY, PHASE_FAILED);
                coronaEvent.put(EVENT_TYPE_KEY, zone.isRewarded() ? TYPE_REWARDEDVIDEO : TYPE_INTERSTITIAL);
                coronaEvent.put(CoronaLuaEvent.ISERROR_KEY, true);
                coronaEvent.put(CoronaLuaEvent.RESPONSE_KEY, RESPONSE_LOADFAILED);
                coronaEvent.put(EVENT_DATA_KEY, data.toString());
                dispatchLuaEvent(coronaEvent);
            }
            super.onRequestNotFilled(zone);
        }
    }

    private class CoronaAdColonyRewardListener implements AdColonyRewardListener {
        @Override
        public void onReward(AdColonyReward adColonyReward) {
            Map<String, Object> coronaEvent = new HashMap<>();
            coronaEvent.put(EVENT_PHASE_KEY, PHASE_REWARD);
            coronaEvent.put(EVENT_TYPE_KEY, TYPE_REWARDEDVIDEO);
            if (adColonyReward.success()) {
                if (!adcolonyObjects.isEmpty()) {
                    ZoneStatusInfo zoneStatus = (ZoneStatusInfo) ((HashMap) adcolonyObjects.get(ZONESTATUS_KEY)).get(adColonyReward.getZoneID());

                    if (zoneStatus != null) {
                        // create data
                        JSONObject data = new JSONObject();
                        try {
                            data.put(DATA_ZONE_NAME, zoneStatus.zoneName);
                            data.put(DATA_CURRENCY_NAME, adColonyReward.getRewardName());
                            data.put(DATA_REWARD, adColonyReward.getRewardAmount());
                        } catch (Exception e) {
                            System.err.println();
                        }

                        // send Corona Lua event
                        coronaEvent.put(EVENT_DATA_KEY, data.toString());
                    }
                }
            }
            dispatchLuaEvent(coronaEvent);
        }
    }
}
