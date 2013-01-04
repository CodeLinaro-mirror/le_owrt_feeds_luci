--[[
LuCI - Lua Configuration Interface

Copyright 2008 Steven Barth <steven@midlink.org>
Copyright 2011 Jo-Philipp Wich <xm@subsignal.org>

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

	http://www.apache.org/licenses/LICENSE-2.0

$Id: network.lua 8785 2012-06-26 21:49:27Z jow $
]]--

module("luci.controller.config.config", package.seeall)

function index()
	local uci = require("luci.model.uci").cursor()
	local root = node()
	if not root.target then
		root.target = alias("config")
		root.index = true
	end

	local page   = node("config")
	page.target  = firstchild()
	page.title   = _("Skifta Audio Module Configurator")
	page.order   = 10
	--page.sysauth = "root"
	--page.sysauth_authenticator = "htmlauth"

	page.index = true
	local has_wifi = false

	uci:foreach("wireless", "wifi-device",
		function(s)
			has_wifi = true
			return false
		end)

	if has_wifi then
		page = entry({"config", "connect"}, template("config/connect"), nil)
		page.leaf = true

		page = entry({"config", "join"}, call("wifi_join"), nil)
		page.leaf = true

		page = entry({"config", "status"}, call("wifi_status"), nil)
		page.leaf = true

		page = entry({"config", "reboot"}, call("sys_reboot"), nil)
		page.leaf = true

		page = entry({"config", "overview"}, template("config/overview"), nil)
		page.leaf = true

		page = entry({"config", "select"}, call("wifi_add_friend_name"), nil)
		page.leaf = true

        local uci = require "luci.model.uci".cursor()
        
        status=uci:get("rygel", "config", "status")

        if status then
		    page = entry({"config", "index"}, template("config/overview"), _("Skifta Audio Module"), 10)
        else
		    page = entry({"config", "index"}, template("config/index"), _("Skifta Audio Module"), 10)
        end
		page.leaf = true
		page.subindex = true
	end
end

function sys_reboot()
	-- TODO: show a reboot UI to user
	luci.template.render("admin_system/sys_reboot")
	luci.sys.reboot()
end

function wifi_add_friend_name()
	local friendly_name = luci.http.formvalue("friendly-name")
	if friendly_name then
		local uci = require "luci.model.uci".cursor()
		uci:set("rygel", "config", "friendly", friendly_name)
		uci:save("rygel")
		uci:commit("rygel")
	end
	luci.template.render("config/select")
end

function wifi_add_apply(f)
	--local dbg = io.open("/tmp/luci-dbg", "w")
	local uci = require "luci.model.uci".cursor()
	local nw = require "luci.model.network".init(uci)

	local wdev = nw:get_wifidev(f.device)
	wdev:set("disabled", false)
	--wdev:set("channel", f.channel)
	--dbg:write(string.format("device %s: channel: %d, ssid: %s\n", wdev:name(), f.channel, f.ssid))
	local n
	for _, n in ipairs(wdev:get_wifinets()) do
		--dbg:write(string.format("delete wifinet %s\n", n:name()))
		wdev:del_wifinet(n)
	end
	local wconf = {
		device  = f.device,
		ssid    = f.ssid,
		mode    = (f.mode == "Ad-Hoc" and "adhoc" or "sta")
	}

	if f.wep == "1" then
		wconf.encryption = "wep-open"
		wconf.key        = "1"
		wconf.key1       = f.key or ""
	elseif (tonumber(f.wpa_version) or 0) > 0 then
		wconf.encryption = (tonumber(f.wpa_version) or 0) >= 2 and "psk2" or "psk"
		wconf.key        = f.key or ""
	else
		wconf.encryption = "none"
	end

	if wconf.mode == "adhoc" then
		wconf.bssid = f.bssid
	end

	-- edit the network.wan to update the interface to wlan0
	-- TODO: change hard-coded later
	net = nw:get_network("wan")
	if net then
		-- the "wan" network exists and not empty
		-- change these options
		uci:set("network", "wan", "proto", "dhcp")
		_orig_if = uci:get("network", "wan", "_orig_if")
		orig_if = uci:get("network", "wan", "ifname")
		if not _orig_if and orig_if and #orig_if > 0 and orig_if ~= "wlan0" then
			uci:set("network", "wan", "_orig_if", orig_if)
		end
		uci:set("network", "wan", "ifname", "wlan0")
		net = nw:get_network("wan")
	else
		net = nw:add_network("wan", { proto = "dhcp", ifname = "wlan0" })
	end
	wconf.network = net:name()
	--dbg:write(string.format("wconf.network %s\n", wconf.network))
	local wnet = wdev:add_wifinet(wconf)
	if wnet then
        -- successful to set all the required information
        -- mark it to be configured
        uci:set("rygel","config","status","configured"); 
		-- Save & commit & apply
        uci:save("rygel")
		uci:save("wireless")
		uci:save("network")
        uci:commit("rygel")
		uci:commit("wireless")
		uci:commit("network")
		local conflist = {"wireless", "network","rygel"}
		uci:apply(conflist)
		--dbg:write("wnet %s: save & commit & apply\n", wnet:name())
		-- Redirect to overview page
	end
	--dbg:close()

	--luci.http.redirect(luci.dispatcher.build_url("admin/network/wireless_overview"))
end

function wifi_join()
	local function param(x)
		return luci.http.formvalue(x)
	end

	local function ptable(x)
		x = param(x)
		return x and (type(x) ~= "table" and { x } or x) or {}
	end

	local params = {
		device = param("device"),
		ssid = param("ssid"),
		channel  = param("channel"),
		mode = param("mode"),
		bssid = param("bssid"),
		wep = param("wep"),
		wpa_suites = param("wpa_suites"),
		wpa_version = param("wpa_version"),
		key = param("key")
	}

	if params.device and params.ssid then
		local cancel  = (param("cancel") or param("cbi.cancel")) and true or false

		if cancel then
			luci.http.redirect(luci.dispatcher.build_url("config/join?device=" .. params.device))
		else
			local rv = { }
			wifi_add_apply(params)
			rv[#rv+1] = 0
			luci.http.prepare_content("application/json")
			luci.http.write_json(rv)
		end
	end
end

function wifi_status()
	local path = luci.dispatcher.context.requestpath
	local s    = require "luci.tools.status"
	local rv   = { }

	local dev
	for dev in path[#path]:gmatch("[%w%.%-]+") do
		rv[#rv+1] = s.wifi_network(dev)
	end

	if #rv > 0 then
		luci.http.prepare_content("application/json")
		luci.http.write_json(rv)
		return
	end

	luci.http.status(404, "No such device")
end
