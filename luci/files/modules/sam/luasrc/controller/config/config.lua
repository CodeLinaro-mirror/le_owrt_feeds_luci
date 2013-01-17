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

		page = entry({"config", "verify_connect"}, call("wifi_verify_connect"), nil)
		page.leaf = true

		page = entry({"config", "check_connect_status"}, call("wifi_check_connect_status"), nil)
		page.leaf = true

		page = entry({"config", "status"}, call("wifi_status"), nil)
		page.leaf = true

		page = entry({"config", "reboot"}, call("sys_reboot"), nil)
		page.leaf = true

		page = entry({"config", "connected"}, template("config/connected"), nil)
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
		uci:foreach("system","system",
		function(s)
		if s[".index"] == 0 then
			cfgName = s[".name"]
		end
		return false
		end
		)
		local no_spaces_name=string.gsub(friendly_name, " ", "_")
		uci:set("system", cfgName, "hostname", no_spaces_name)
		uci:set("system", cfgName, "friendly_name", friendly_name)
		uci:save("system")
		uci:commit("system")
		os.execute("STATE=friendly_name /etc/statemgr >> /dev/null")
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

	-- edit the network.wan to update the interface to wlan0/ath0
	-- TODO: change hard-coded later
	local wifname;
	if f.device == "wifi0" then
		wifname = "ath0"
	else
		wifname = "wlan0"
	end
	net = nw:get_network("wan")
	if net then
		-- the "wan" network exists and not empty
		-- change these options
		uci:set("network", "wan", "proto", "dhcp")
		_orig_if = uci:get("network", "wan", "_orig_if")
		orig_if = uci:get("network", "wan", "ifname")
		if not _orig_if and orig_if and #orig_if > 0 and orig_if ~= wifname then
			uci:set("network", "wan", "_orig_if", orig_if)
		end
		uci:set("network", "wan", "ifname", wifname)
		net = nw:get_network("wan")
	else
		net = nw:add_network("wan", { proto = "dhcp", ifname = wifname })
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

function wifi_verify_connect()
        local dbg = io.open("/tmp/luci-dbg", "w")
        local function param(x)
                return luci.http.formvalue(x)
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
        local function get_encryption()
                local encrypt
                if params.wep == "1" then
                        encrypt = "wep-open"
                elseif (tonumber(params.wpa_version) or 0) > 0 then
                        encrypt = (tonumber(params.wpa_version) or 0) >= 2 and "psk2" or "psk"
                else
                        encrypt = "none"
                end
                return encrypt
        end

        if params.device and params.ssid then
                local uci = require "luci.model.uci".cursor()
                local lnk_stat = luci.sys.call("/usr/sbin/stavap %s %s %s %s %s 2>/dev/null 1>&2" %{ params.ssid, params.bssid, params.channel,  get_encryption(), params.key })
                dbg:write(string.format("wifi_join status: %d, ssid: %s, bssid: %s, channel: %s, encryption: %s, key: %s\n", lnk_stat, params.ssid, params.bssid, params.channel, get_encryption(), params.key))
                uci:set("skifta", "config", "internal")
                uci:set("skifta", "config", "connect", lnk_stat)
                uci:set("skifta", "config", "device", params.device)
                uci:set("skifta", "config", "ssid", params.ssid)
                uci:set("skifta", "config", "bssid", params.bssid)
                uci:set("skifta", "config", "channel", params.channel)
                uci:set("skifta", "config", "mode", params.mode)
                uci:set("skifta", "config", "wep", params.wep)
                uci:set("skifta", "config", "wpa_suites", params.wpa_suites)
                uci:set("skifta", "config", "wpa_version", params.wpa_version)
                uci:set("skifta", "config", "key", params.key)
                uci:save("skifta")
                uci:commit("skifta")
        end
        dbg:close()
end

function wifi_check_connect_status()
        local uci = require "luci.model.uci".cursor()
        uci:load("skifta")
        local lnk_stat = uci:get("skifta", "config", "connect")
        if lnk_stat == '0' then
                luci.template.render("config/connected")
        else
                luci.template.render("config/select")
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
