local gp = sdk.get_native_singleton("via.hid.GamePad"); local td = sdk.find_type_definition("via.hid.GamePad")
local dev = sdk.call_native_func(gp, td, "get_MergedDevice") or sdk.call_native_func(gp, td, "getMergedDevice", 0)
if not dev then return "no device" end
return string.format("AnalogR %.2f AnalogL %.2f", dev:call("get_AnalogR"), dev:call("get_AnalogL"))
