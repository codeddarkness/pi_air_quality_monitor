# pi_air_quality_monitor Makefile v1.2.0
-include config.env
export

PAQM_USER            ?= pi
PAQM_DIR             ?= $(shell pwd)
PAQM_PORT            ?= 8000
COMPOSE_PROJECT_NAME ?= pi_air_quality_monitor

.PHONY: run stop restart status build install validate copy shell log api metrics

run:
	@source scripts/service/aqi_monitor.func && aqi_monitor start
stop:
	@source scripts/service/aqi_monitor.func && aqi_monitor stop
restart:
	@source scripts/service/aqi_monitor.func && aqi_monitor restart
status:
	@source scripts/service/aqi_monitor.func && aqi_monitor status
build:
	@docker compose build
install:
	@bash install.sh
validate:
	@bash -c 'echo "=== Sensor ==="; ls /dev/ttyUSB* 2>/dev/null || echo "  not found"; echo "=== Containers ==="; docker ps --filter name=$(COMPOSE_PROJECT_NAME) --format "  {{.Names}} - {{.Status}}"; echo "=== API ==="; curl -sf http://localhost:$(PAQM_PORT)/api/ | python3 -c "import json,sys; d=json.load(sys.stdin); print(\"  readings:\",len(d[\"historical\"][\"labels\"]),\"| AQI:\",d[\"historical\"][\"aqi\"][\"data\"][-1])" 2>/dev/null || echo "  not responding"; echo "=== Metrics ==="; curl -sf http://localhost:$(PAQM_PORT)/metrics | grep -E "^aqi|^pm" || echo "  not responding"'
copy:
	@test -n "$(TARGET_HOST)" || (echo "Usage: make copy TARGET_HOST=user@host"; exit 1)
	rsync -av $(PAQM_DIR)/ --exclude .git --exclude data/redis --exclude logs --exclude _local_data --exclude '*.pyc' --exclude config.env $(TARGET_HOST):$(PAQM_DIR)/
shell:
	@test -n "$(TARGET_HOST)" || (echo "Usage: make shell TARGET_HOST=user@host"; exit 1)
	ssh $(TARGET_HOST)
log:
	@tail -f /tmp/sensor_logs/aqi_monitor.log
api:
	@curl -s http://localhost:$(PAQM_PORT)/api/ | python3 -m json.tool
metrics:
	@curl -s http://localhost:$(PAQM_PORT)/metrics
