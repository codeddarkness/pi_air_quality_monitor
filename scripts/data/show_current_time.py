#!/usr/bin/env python3
import json
import os
import time
import datetime


from datetime import datetime, timezone, timedelta

#timezone_offset = -8.0  # Pacific Standard Time (UTC−08:00)
timezone_offset = -6.0  # America/Denver (MDT, -0600)
tz_info = timezone(timedelta(hours=timezone_offset))
current_time = datetime.now(tz_info)

print(current_time)
