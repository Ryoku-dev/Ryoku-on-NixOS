#!/usr/bin/env python3
# Serves the Wellbeing tab from Ryoku's own screen-time store
# ($XDG_STATE_HOME/ryoku/screentime.json, written by shell/services/ScreenTime.qml)
# in the shape Serpantinum's focus database produced. Ryoku banks whole hours per
# app, so the half-hour chart and the peak window work at hour resolution.
import argparse
import calendar
import json
import os
from datetime import date, timedelta


def store_path():
    state = os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state")
    return os.path.join(state, "ryoku", "screentime.json")


def load_days(path):
    try:
        with open(path) as f:
            days = json.load(f).get("days", {})
        return days if isinstance(days, dict) else {}
    except (OSError, ValueError):
        return {}


def day_total(days, key, app):
    entry = days.get(key) or {}
    if app:
        return int((entry.get("apps") or {}).get(app, 0))
    return int(entry.get("total", 0))


def day_hours(days, key, app):
    entry = days.get(key) or {}
    hours = ((entry.get("appHours") or {}).get(app) if app else entry.get("hours")) or []
    return [int(h) for h in hours[:24]] + [0] * (24 - len(hours[:24]))


def app_rows(totals):
    whole = sum(totals.values())
    rows = sorted(totals.items(), key=lambda kv: kv[1], reverse=True)
    return [{
        "class": cls, "name": cls, "seconds": secs,
        "percent": round(secs / whole * 100, 1) if whole > 0 else 0,
    } for cls, secs in rows]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("date", nargs="?", default=date.today().isoformat())
    parser.add_argument("--app", type=str, default=None)
    parser.add_argument("--store", type=str, default=None)
    args = parser.parse_args()

    try:
        target = date.fromisoformat(args.date)
    except ValueError:
        target = date.today()
    target_key = target.isoformat()
    app = args.app
    days = load_days(args.store or store_path())

    monday = target - timedelta(days=target.weekday())
    sunday = monday + timedelta(days=6)
    week_keys = [(monday + timedelta(days=i)).isoformat() for i in range(7)]

    week_totals = [day_total(days, k, app) for k in week_keys]
    used_days = sum(1 for t in week_totals if t > 0)
    average = sum(week_totals) // used_days if used_days else 0

    today_apps = {}
    week_apps = {}
    for key in week_keys:
        for cls, secs in ((days.get(key) or {}).get("apps") or {}).items():
            if app and cls != app:
                continue
            week_apps[cls] = week_apps.get(cls, 0) + int(secs)
            if key == target_key:
                today_apps[cls] = int(secs)

    day_names = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    week = [{"date": k, "day": day_names[i], "total": week_totals[i], "is_target": k == target_key}
            for i, k in enumerate(week_keys)]

    first = target.replace(day=1)
    month = [{"date": "", "total": -1, "is_target": False} for _ in range(first.weekday())]
    for d in range(1, calendar.monthrange(target.year, target.month)[1] + 1):
        key = target.replace(day=d).isoformat()
        month.append({"date": key, "total": day_total(days, key, app), "is_target": key == target_key})

    hourly = [0] * 48
    for hour, secs in enumerate(day_hours(days, target_key, app)):
        hourly[hour * 2] = secs // 2
        hourly[hour * 2 + 1] = secs - secs // 2

    heatmap = [day_hours(days, k, app) for k in week_keys]
    by_hour = [sum(day[h] for day in heatmap) for h in range(24)]
    peak = max(range(24), key=lambda h: by_hour[h])
    peak_str = f"{peak:02d}:00 - {(peak + 1) % 24:02d}:00" if by_hour[peak] > 0 else "N/A"

    known = {}
    for entry in days.values():
        for cls, secs in ((entry or {}).get("apps") or {}).items():
            known[cls] = known.get(cls, 0) + int(secs)

    print(json.dumps({
        "selected_date": target_key,
        "total": day_total(days, target_key, app),
        "average": average,
        "week_range": f"{monday.strftime('%b')} {monday.day} - {sunday.strftime('%b')} {sunday.day}",
        "yesterday": day_total(days, (target - timedelta(days=1)).isoformat(), app),
        "current": app if app else "History",
        "apps": app_rows(today_apps),
        "week_apps": app_rows(week_apps)[:50],
        "week": week,
        "month": month,
        "hourly": hourly,
        "week_heatmap": heatmap,
        "peak_usage_str": peak_str,
        "all_known_apps": [{"class": cls, "name": cls}
                           for cls, _ in sorted(known.items(), key=lambda kv: kv[1], reverse=True)],
    }))


if __name__ == "__main__":
    main()
