//
//  AdColonyPlugin.h
//  AdColony Plugin
//
//  Copyright (c) 2016 Corona Labs Inc. All rights reserved.
//

#ifndef _AdColonyPlugin_H_
#define _AdColonyPlugin_H_

#import "CoronaLua.h"
#import "CoronaMacros.h"

// This corresponds to the name of the library, e.g. [Lua] require "plugin.library"
// where the '.' is replaced with '_'
CORONA_EXPORT int luaopen_plugin_adcolony( lua_State *L );

#endif // _AdColonyPlugin_H_
