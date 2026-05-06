#!/usr/bin/env bash
cd ~/pi_air_quality_monitor
# Add the grafana-friendly endpoint
python3 - << 'EOF'
content = open('src/app.py').read()
new_route = '''
@app.route('/api/grafana/')
@cross_origin()
def api_grafana():
    """Row-oriented JSON for Grafana Infinity datasource."""
    data = reconfigure_data(aqm.get_last_n_measurements())
    rows = [
        {'timestamp': ts, 'aqi': data['aqi']['data'][i],
         'pm10': data['pm10']['data'][i], 'pm25': data['pm2']['data'][i]}
        for i, ts in enumerate(data['labels'])
    ]
    return jsonify(rows)

'''
# Insert before the if __name__ block
content = content.replace("\nif __name__", new_route + "\nif __name__")
open('src/app.py', 'w').write(content)
print('OK')
EOF

docker compose restart web
sleep 5
curl -s http://localhost:8000/api/grafana/ | python3 -m json.tool | head -20
