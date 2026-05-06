# app.py v1.3.1
import os
import time
from flask import Flask, jsonify, render_template, Response
from AirQualityMonitor import AirQualityMonitor
from apscheduler.schedulers.background import BackgroundScheduler
import atexit
from flask_cors import CORS, cross_origin

app = Flask(__name__)
CORS(app)
app.config['CORS_HEADERS'] = 'Content-Type'
aqm = AirQualityMonitor()

scheduler = BackgroundScheduler()
scheduler.add_job(func=aqm.save_measurement_to_redis, trigger="interval", seconds=60)
scheduler.start()
atexit.register(lambda: scheduler.shutdown())


def pretty_timestamps(measurement):
    return [x['measurement']['timestamp'].split('.')[0] for x in measurement]


def reconfigure_data(measurement):
    measurement = list(reversed(measurement[:30]))
    return {
        'labels': pretty_timestamps(measurement),
        'aqi':  {'label': 'aqi',   'data': [x['measurement']['aqi']    for x in measurement],
                 'backgroundColor': '#f0b429', 'borderColor': '#f0b429', 'borderWidth': 3},
        'pm10': {'label': 'pm10',  'data': [x['measurement']['pm10']   for x in measurement],
                 'backgroundColor': '#ff6b6b', 'borderColor': '#ff6b6b', 'borderWidth': 3},
        'pm2':  {'label': 'pm2.5', 'data': [x['measurement']['pm2.5'] for x in measurement],
                 'backgroundColor': '#42C0FB', 'borderColor': '#42C0FB', 'borderWidth': 3},
    }


@app.route('/')
def index():
    return render_template('index.html',
        context={'historical': reconfigure_data(aqm.get_last_n_measurements())})


@app.route('/api/')
@cross_origin()
def api():
    """Historical data in Chart.js format (last 30 readings)."""
    return jsonify({'historical': reconfigure_data(aqm.get_last_n_measurements())})


@app.route('/api/now/')
@cross_origin()
def api_now():
    """Single live reading from sensor."""
    return jsonify({'current': aqm.get_measurement()})


@app.route('/api/grafana/')
@cross_origin()
def api_grafana():
    """Row-oriented JSON for Grafana Infinity datasource.

    Returns an array of objects with timestamp, aqi, pm10, pm25.
    Each row is one sensor reading, ordered oldest to newest.

    Example row:
        {"timestamp": "2026-05-05 19:22:39", "aqi": 7, "pm10": 3.3, "pm25": 1.6}

    Grafana Infinity setup:
        Type: JSON | Parser: Default | Format: Table
        Rows/Root: $[*]
        Columns: timestamp (Time), aqi (Number), pm10 (Number), pm25 (Number)
    """
    data = reconfigure_data(aqm.get_last_n_measurements())
    rows = [
        {
            'timestamp': ts,
            'aqi':  data['aqi']['data'][i],
            'pm10': data['pm10']['data'][i],
            'pm25': data['pm2']['data'][i],
        }
        for i, ts in enumerate(data['labels'])
    ]
    return jsonify(rows)


@app.route('/metrics')
def metrics():
    """Prometheus text format — scrape target for Prometheus or Grafana HTTP datasource."""
    try:
        data = aqm.get_last_n_measurements()
        if not data:
            return Response('# No data yet\n', mimetype='text/plain; version=0.0.4')
        latest = data[0]['measurement']
        ts_ms  = int(data[0]['time'] * 1000)
        out = (
            '# HELP aqi_index Air Quality Index (EPA)\n'
            '# TYPE aqi_index gauge\n'
            f'aqi_index {latest["aqi"]} {ts_ms}\n'
            '# HELP pm10_ugm3 PM10 particulate matter ug/m3\n'
            '# TYPE pm10_ugm3 gauge\n'
            f'pm10_ugm3 {latest["pm10"]} {ts_ms}\n'
            '# HELP pm25_ugm3 PM2.5 particulate matter ug/m3\n'
            '# TYPE pm25_ugm3 gauge\n'
            f'pm25_ugm3 {latest["pm2.5"]} {ts_ms}\n'
            '# HELP aqi_readings_total Total readings stored in Redis\n'
            '# TYPE aqi_readings_total counter\n'
            f'aqi_readings_total {len(data)}\n'
        )
        return Response(out, mimetype='text/plain; version=0.0.4')
    except Exception as e:
        return Response(f'# Error: {e}\n', mimetype='text/plain; version=0.0.4', status=500)


if __name__ == "__main__":
    app.run(debug=True, use_reloader=False, host='0.0.0.0',
            port=int(os.environ.get('PORT', '8000')))
