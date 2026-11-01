import json, time, sys, os
D = r"C:SteamsteamappsmmonResident Evil Village BIOHAZARD VILLAGEeframeworkdataisceral_re8"
key_file = os.path.join(os.path.dirname(os.path.abspath(__file__)), "openkey.txt")
end = time.time() + 1500
while time.time() < end:
    try: key = open(key_file).read().strip()
    except Exception: key = ""
    if key == "stop": break
    with open(D + "/zones_open.json.tmp", "w") as f: f.write(json.dumps({"key": key, "t": int(time.time())}))
    os.replace(D + "/zones_open.json.tmp", D + "/zones_open.json")
    time.sleep(1)
