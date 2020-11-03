--
--  main.lua
--  AdColony Sample App
--
--  Copyright (c) 2016 Corona Labs Inc. All rights reserved.
--

local adcolony = require("plugin.adcolony")
local widget = require("widget")
local json = require("json")

--------------------------------------------------------------------------
-- set up UI
--------------------------------------------------------------------------

local interstitialButton
local rewardedButton

display.setStatusBar( display.HiddenStatusBar )
display.setDefault("background", 1)

local adcolonyLogo = display.newImage("logo-adcolony-600x.png")
adcolonyLogo.anchorY = 0
adcolonyLogo.x, adcolonyLogo.y = display.contentCenterX, 0
adcolonyLogo:scale(0.3, 0.3)

local subTitle = display.newText {
  text = "plugin for Corona SDK",
  x = display.contentCenterX,
  y = 50,
  font = display.systemFont,
  fontSize = 14
}
subTitle:setFillColor(0.3)

local eventDataTextBox = native.newTextBox( display.contentCenterX, display.contentHeight - 100, 310, 200)
eventDataTextBox.placeholder = "Event data will appear here"

processEventTable = function(event)
  local logString = json.prettify(event):gsub("\\","")
  logString = "\nPHASE: "..event.phase.." - - - - - - - - - - - -\n" .. logString
  print(logString)
  eventDataTextBox.text = logString .. eventDataTextBox.text
end

--------------------------------------------------------------------------
-- plugin implementation
--------------------------------------------------------------------------

local appId = "n/a"
local adZones = {}
local platformName = system.getInfo("platformName")

if platformName == "Android" then
  if system.getInfo("targetAppStore") == "amazon" then
    appId = "app022c863a0bd044b580"
    adZones = {interstitial="vzd3edac151669436fb0", rewardedVideo="vz026b1d196f6c4e9898"}
  else -- Google Play
    appId = "app93d88471b8064af082"
    adZones = {interstitial="vzd0d91d3fe357403b97", rewardedVideo="vz7d8e59fc7c074471b0"}
  end
elseif platformName == "iPhone OS" then
  appId = "app4a776411414e465d87"
  adZones = {interstitial="vz287414efb3f04229ac", rewardedVideo="vz59e1fa6deb5b486db4"}
else
  print "Unsupported platform"
end

print("App ID: "..appId)
print("Ad zones: "..json.prettify(adZones))

local adcolonyListener = function(event)
  processEventTable(event)

  local data = (event.data ~= nil) and json.decode(event.data) or {}

  if event.phase == "init" then
    if (adcolony.isLoaded("interstitial")) then
      interstitialButton:setLabel("Show interstitial")
    end

    if (adcolony.isLoaded("rewardedVideo")) then
      rewardedButton:setLabel("Show rewarded video")
    end

  elseif event.phase == "loaded" then
    if data.zoneName == "interstitial" then
      interstitialButton:setLabel("Show interstitial video")
    elseif data.zoneName == "rewardedVideo" then
      rewardedButton:setLabel("Show rewarded video")
    end

  elseif event.phase == "failed" then
    if data.zoneName == "interstitial" then
      interstitialButton:setLabel("Load interstitial video")
    elseif data.zoneName == "rewardedVideo" then
      rewardedButton:setLabel("Load rewarded video")
    end
  end
end

adcolony.init(adcolonyListener, {
  appId = appId,
  adZones = adZones,
  adOrientation = "landscape",
  debugLogging = true,
  hasUserConsent = true
})

interstitialButton = widget.newButton {
  label = "Load interstitial...",
  width = 300,
  onRelease = function(event)
    if adcolony.isLoaded("interstitial") then
      interstitialButton:setLabel("Load interstitial video...")
      adcolony.show("interstitial")
    else
      interstitialButton:setLabel("Loading interstitial video...")
      adcolony.load("interstitial")
    end
  end
}

interstitialButton.x, interstitialButton.y = display.contentCenterX, 100

rewardedButton = widget.newButton {
  label = "Load rewarded video...",
  width = 300,
  onRelease = function(event)
    if adcolony.isLoaded("rewardedVideo") then
      rewardedButton:setLabel("Load rewarded video...")
      adcolony.show("rewardedVideo")
    else
      rewardedButton:setLabel("Loading rewarded video...")
      adcolony.load("rewardedVideo", { postPopup=true })
    end
  end
}

rewardedButton.x, rewardedButton.y = display.contentCenterX, 150
