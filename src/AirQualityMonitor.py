import json
import os
import time
import datetime
import threading
import serial
import redis
import aqi
from sds011lib import SDS011QueryReader

redis_client = redis.StrictRedis(host=os.environ.get('REDIS_HOST'), port=6379, db=0)


class AirQualityMonitor():

    def __init__(self):
        self.ser = SDS011QueryReader('/dev/ttyUSB0')
        self._lock = threading.Lock()

    def get_measurement(self):
        # Fail fast (15s) instead of blocking forever if the scheduler or
        # another request already holds the serial handle. Previously
        # unlocked concurrent access to self.ser could hang a request
        # indefinitely with no exception, eventually starving all Flask
        # workers (including routes with no serial access at all).
        if not self._lock.acquire(timeout=15):
            raise TimeoutError("Sensor busy (concurrent read in progress) - try again shortly")
        try:
            self.data = []
            for index in range(0, 10):
                datum = self.ser.query()
                self.data.append(datum)
            self.pmtwo = datum.pm25
            self.pmten = datum.pm10
            # PAQM_DIAG_CLAMP_PATCH — python-aqi 0.6.1's EPA breakpoint table
            # tops out at PM2.5=500.4 / PM10=604 ug/m3 and raises IndexError
            # past that instead of clamping. Clamp to the table max and fall
            # back to AQI=500 (Hazardous ceiling) if it still throws.
            pm25_clamped = min(self.pmtwo, 500.4)
            pm10_clamped = min(self.pmten, 604.0)
            try:
                myaqi = aqi.to_aqi([(aqi.POLLUTANT_PM25, str(pm25_clamped)),
                                    (aqi.POLLUTANT_PM10, str(pm10_clamped))])
                self.aqi = float(myaqi)
            except IndexError:
                self.aqi = 500.0

            self.meas = {
                "timestamp": datetime.datetime.now(),
                "pm2.5": self.pmtwo,
                "pm10": self.pmten,
                "aqi": self.aqi,
            }

            return {
                'time': int(time.time()),
                'measurement': self.meas
            }
        finally:
            self._lock.release()

    def save_measurement_to_redis(self):
        """Saves measurement to redis db"""
        # PAQM_DIAG_TRIM_PATCH — list was never trimmed and reached 175,630+
        # entries; every read (get_last_n_measurements) was pulling ALL of
        # them just to use the last 30, pegging CPU and getting slower with
        # every call. Cap it here going forward.
        redis_client.lpush('measurements', json.dumps(self.get_measurement(), default=str))
        redis_client.ltrim('measurements', 0, 99)

    def get_last_n_measurements(self):
        """Returns the last n measurements in the list"""
        # PAQM_DIAG_TRIM_PATCH — bounded to 0,99 instead of 0,-1 (was
        # unbounded; see save_measurement_to_redis for the trim side).
        return [json.loads(x) for x in redis_client.lrange('measurements', 0, 99)]
