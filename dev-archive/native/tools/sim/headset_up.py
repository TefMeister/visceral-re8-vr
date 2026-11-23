"""headset_up.py [wait seconds] -- is a headset streaming right now? (2026-11-23: the desk headset had gone to sleep and Village
started flat: `XR_ERROR_FORM_FACTOR_UNAVAILABLE` in the loader's log, found only after a whole launch.) Asks the PC's OpenXR
runtime for a head-mounted system, the same two calls the loader makes, with no game running. Prints UP or DOWN (and the
runtime's answer); exit code 0 = up, 1 = down. With a number it asks every 20 s until up or the seconds run out."""
import ctypes, glob, os, sys, time

LOADERS = glob.glob("C:/Steam/steamapps/common/Resident Evil Village BIOHAZARD VILLAGE/openxr_loader.dll") + \
          glob.glob("C:/Steam/steamapps/common/*/openxr_loader.dll")
NAMES = {0: "XR_SUCCESS", -2: "XR_ERROR_RUNTIME_FAILURE", -9: "XR_ERROR_EXTENSION_NOT_PRESENT", -10: "XR_ERROR_RUNTIME_UNAVAILABLE",
         -51: "XR_ERROR_FORM_FACTOR_UNAVAILABLE", -50: "XR_ERROR_FORM_FACTOR_UNSUPPORTED"}

class AppInfo(ctypes.Structure):
    _fields_ = [("applicationName", ctypes.c_char * 128), ("applicationVersion", ctypes.c_uint32),
                ("engineName", ctypes.c_char * 128), ("engineVersion", ctypes.c_uint32), ("apiVersion", ctypes.c_uint64)]
class CreateInfo(ctypes.Structure):
    _fields_ = [("type", ctypes.c_int32), ("next", ctypes.c_void_p), ("createFlags", ctypes.c_uint64), ("app", AppInfo),
                ("layerCount", ctypes.c_uint32), ("layers", ctypes.c_void_p), ("extCount", ctypes.c_uint32), ("exts", ctypes.c_void_p)]
class GetInfo(ctypes.Structure):
    _fields_ = [("type", ctypes.c_int32), ("next", ctypes.c_void_p), ("formFactor", ctypes.c_int32)]

def ask():
    if not LOADERS:
        return None, "no openxr_loader.dll found"
    xr = ctypes.CDLL(LOADERS[0])
    ci = CreateInfo(type=3); ci.app.applicationName = b"headset_up"; ci.app.apiVersion = (1 << 48) | 22
    inst = ctypes.c_uint64(0)
    r = xr.xrCreateInstance(ctypes.byref(ci), ctypes.byref(inst))
    if r != 0:
        return False, "no runtime instance: " + NAMES.get(r, str(r))
    gi = GetInfo(type=4, formFactor=1); sid = ctypes.c_uint64(0)
    xr.xrGetSystem.argtypes = [ctypes.c_uint64, ctypes.c_void_p, ctypes.c_void_p]
    r = xr.xrGetSystem(inst.value, ctypes.byref(gi), ctypes.byref(sid))
    xr.xrDestroyInstance.argtypes = [ctypes.c_uint64]; xr.xrDestroyInstance(inst.value)
    return r == 0, NAMES.get(r, str(r))

if __name__ == "__main__":
    wait = float(sys.argv[1]) if len(sys.argv) > 1 else 0; t0 = time.time()
    while True:
        up, why = ask()
        if up or time.time() - t0 >= wait:
            break
        time.sleep(20)
    print(("UP" if up else "DOWN") + ": " + why); sys.exit(0 if up else 1)
