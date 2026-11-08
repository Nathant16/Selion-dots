#!/usr/bin/env python3
import sys, json, urllib.request

lat = sys.argv[1] if len(sys.argv) > 1 else '55.04'
lon = sys.argv[2] if len(sys.argv) > 2 else '82.93'

url = f'https://wttr.in/{lat},{lon}?format=j1'
req = urllib.request.Request(url, headers={'User-Agent': 'curl/8.0'})

try:
    with urllib.request.urlopen(req, timeout=5) as resp:
        data = json.loads(resp.read().decode('utf-8'))
except Exception as e:
    sys.exit(1)

def wwo_to_wmo(code):
    try: c = int(code)
    except: return 3
    if c == 113: return 0
    if c in (116, 119): return 2
    if c == 122: return 3
    if c in (143, 248, 260): return 45
    if c in (176, 263, 266, 281, 284, 293, 296, 299, 302, 305, 308, 311, 314, 353, 356, 359): return 61
    if c in (179, 182, 185, 227, 230, 317, 320, 323, 326, 329, 332, 335, 338, 350, 362, 365, 368, 371, 374, 377): return 71
    if c in (200, 386, 389, 392, 395): return 95
    return 3

curr = data.get('current_condition', [{}])[0]
times, temps, feels, pops, codes, hums, winds = [], [], [], [], [], [], []

for day in data.get('weather', []):
    d_str = day.get('date', '')
    for h in day.get('hourly', []):
        t_int = int(h.get('time', 0)) // 100
        times.append(f'{d_str}T{t_int:02d}:00')
        temps.append(float(h.get('tempC', 0)))
        feels.append(float(h.get('FeelsLikeC', 0)))
        pops.append(int(h.get('chanceofrain', 0)))
        codes.append(wwo_to_wmo(h.get('weatherCode', 113)))
        hums.append(int(h.get('humidity', 0)))
        winds.append(float(h.get('windspeedKmph', 0)))

om_data = {
    'current': {
        'temperature_2m': float(curr.get('temp_C', 0)),
        'weather_code': wwo_to_wmo(curr.get('weatherCode', 113)),
        'is_day': 1
    },
    'hourly': {
        'time': times,
        'temperature_2m': temps,
        'apparent_temperature': feels,
        'precipitation_probability': pops,
        'weather_code': codes,
        'relative_humidity_2m': hums,
        'wind_speed_10m': winds
    }
}

print(json.dumps(om_data))
