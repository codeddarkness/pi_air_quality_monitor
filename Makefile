# pi_air_quality_monitor Makefile v1.0.1
PI_IP_ADDRESS=10.0.0.194
PI_USERNAME=pi

.PHONY: run stop restart status build install validate copy shell log api

run:
	@source scripts/service/aqi_monitor.func && aqi_monitor start

stop:
	@source scripts/service/aqi_monitor.func && aqi_monitor stop

restart:
	@source scripts/service/aqi_monitor.func && aqi_monitor restart

status:
	@source scripts/service/aqi_monitor.func && aqi_monitor status

build:
	@docker-compose build

install:
	@bash install.sh

validate:
	@bash -c 'REPO=$(pwd); \
	  echo "Sensor:"; ls /dev/ttyUSB* 2>/dev/null || echo "  not found"; \
	  echo "Containers:"; docker ps --filter name=pi_air_quality_monitor --format "  {{.Names}} {{.Status}}"; \
	  echo "API:"; curl -sf http://localhost:8000/api/ | python3 -c \
	    "import json,sys; d=json.load(sys.stdin); \
	     print(\"  readings:\", len(d[\"historical\"][\"labels\"]), \
	           \"| latest:\", d[\"historical\"][\"labels\"][-1], \
	           \"| AQI:\", d[\"historical\"][\"aqi\"][\"data\"][-1])" 2>/dev/null || echo "  API not responding"'

copy:
	@rsync -av $(shell pwd)/ --exclude .git --exclude data/redis --exclude logs \
	  --exclude _local_data --exclude json_data --exclude '*.pyc' \
	  $(PI_USERNAME)@$(PI_IP_ADDRESS):/home/$(PI_USERNAME)/pi_air_quality_monitor/

shell:
	@ssh $(PI_USERNAME)@$(PI_IP_ADDRESS)

log:
	@tail -f /tmp/sensor_logs/aqi_monitor.log

api:
	@curl -s http://$(PI_IP_ADDRESS):8000/api/ | python3 -m json.tool 2>/dev/null \
	  || curl -s http://$(PI_IP_ADDRESS):8000/api/
