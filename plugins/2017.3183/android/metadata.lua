local metadata =
{
    plugin =
    {
        format = 'jar',
        manifest = 
        {
            permissions = {},
            usesPermissions =
            {
                "android.permission.INTERNET",
                "android.permission.ACCESS_NETWORK_STATE",
                "android.permission.WRITE_EXTERNAL_STORAGE"
            },
            usesFeatures = 
            {
            },
            applicationChildElements =
            {
                [[
                    <activity android:name="com.adcolony.sdk.AdColonyInterstitialActivity"
                    android:configChanges="keyboardHidden|orientation|screenSize"
                    android:hardwareAccelerated="true"/>

                    <activity android:name="com.adcolony.sdk.AdColonyAdViewActivity"
                    android:configChanges="keyboardHidden|orientation|screenSize"
                    android:hardwareAccelerated="true"/>
                ]]
            }
        }
    },

    coronaManifest = {
        dependencies = {
            ["shared.google.play.services.ads.identifier"] = "com.coronalabs"
        }
    }
}

return metadata
