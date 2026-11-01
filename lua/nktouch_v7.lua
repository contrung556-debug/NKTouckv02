-- NKTouch V7 extension layer
-- SPDX-License-Identifier: GPL-3.0-or-later
local nk=require("nktouch")
if not nk.http then nk.http=require("nknet") end
if not nk.json then nk.json=require("nkjson") end
nk.NETWORK_VERSION="0.7.4"
return nk
