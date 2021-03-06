import os
import logging
import datetime

from celery.schedules import crontab

from chronam.settings import *

APP_DIR = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))


CELERY_IMPORTS = ("chronam.core.tasks",)
CELERYD_LOG_FILE = os.path.join("/logs/celery", "celery.log")
CELERYD_LOG_LEVEL = logging.INFO
CELERYD_CONCURRENCY = 2

CELERYBEAT_SCHEDULE = {
    "poll_cts": {
        "task": "chronam.core.tasks.poll_cts",
        "schedule": datetime.timedelta(hours=4),
        "args": ()
    },
    "poll_purge": {
        "task": "chronam.core.tasks.poll_purge",
        "schedule": crontab(hour=3, minute=0),
    },
    # Executes every morning at 2:00 A.M
    "delete_django_cache": {
        "task": "chronam.core.tasks.delete_django_cache",
        "schedule": crontab(hour=2, minute=0),
    }
}

CELERYBEAT_LOG_FILE = os.path.join("/logs/celery", "celerybeat.log")
CELERYBEAT_LOG_LEVEL = logging.INFO
