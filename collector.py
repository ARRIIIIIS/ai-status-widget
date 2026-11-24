#!/usr/bin/env python3
"""Data collector for AIStatusWidget (Antigravity & WorkBuddy)."""

import datetime
import glob
import json
import re
import sqlite3
import urllib.request
from pathlib import Path

APP_SUPPORT_DIR = Path.home() / "Library" / "Application Support" / "AIStatusWidget"
CONFIG_PATH = APP_SUPPORT_DIR / "config.json"

DEFAULT_CONFIG = {
    "locale": "en",
    "refresh_interval_sec": 30,
    "antigravity": {
        "reset_at": None,
    },
    "workbuddy": {
        "credits_anchor_value": None,
        "credits_anchor_at_ms": None,
        "reset_at": None,
    },
}


def load_or_create_config():
    APP_SUPPORT_DIR.mkdir(parents=True, exist_ok=True)
    if not CONFIG_PATH.exists():
        CONFIG_PATH.write_text(
            json.dumps(DEFAULT_CONFIG, indent=2, ensure_ascii=False),
            encoding="utf-8",
        )
        return json.loads(json.dumps(DEFAULT_CONFIG))
    try:
        data = json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
        for k, v in DEFAULT_CONFIG.items():
            if k not in data:
                data[k] = v
        return data
    except Exception:
        return json.loads(json.dumps(DEFAULT_CONFIG))


def estimate_tokens(text):
    if not text:
        return 0
    cjk = len(re.findall(r"[\u4e00-\u9fff]", text))
    other = max(0, len(text) - cjk)
    return int(cjk * 1.2 + other / 4.0)


def parse_iso_to_seconds(iso_str):
    if not iso_str:
        return None
    try:
        target = datetime.datetime.fromisoformat(iso_str.replace("Z", "+00:00"))
        now = datetime.datetime.now(datetime.timezone.utc) if target.tzinfo else datetime.datetime.now()
        return max(0, int((target - now).total_seconds()))
    except Exception:
        return None


def collect_antigravity_daemon():
    daemon_dir = Path.home() / ".gemini" / "antigravity" / "daemon"
    if not daemon_dir.exists():
        return None

    hub_files = sorted(daemon_dir.glob("hub_*.json"), key=lambda p: p.stat().st_mtime, reverse=True)
    for hub_file in hub_files:
        try:
            hub = json.loads(hub_file.read_text(encoding="utf-8"))
            port = hub.get("httpPort")
            csrf = hub.get("csrfToken")
            if not port or not csrf:
                continue
            req = urllib.request.Request(
                f"http://127.0.0.1:{port}/exa.language_server_pb.LanguageServerService/GetUserStatus",
                data=b"{}",
                headers={
                    "Content-Type": "application/json",
                    "X-Codeium-Csrf-Token": csrf,
                },
                method="POST",
            )
            with urllib.request.urlopen(req, timeout=1.5) as resp:
                body = json.loads(resp.read().decode("utf-8"))
            user_status = body.get("userStatus", {})
            models = user_status.get("cascadeModelConfigData", {}).get("clientModelConfigs", [])
            gemini_frac = None
            gemini_reset = None
            claude_frac = None
            claude_reset = None
            for m in models:
                label = str(m.get("label", ""))
                qi = m.get("quotaInfo")
                if not isinstance(qi, dict) or "remainingFraction" not in qi:
                    continue
                frac = qi.get("remainingFraction")
                r_sec = parse_iso_to_seconds(qi.get("resetTime"))
                if "Claude" in label or "GPT" in label:
                    if claude_frac is None or (isinstance(frac, (int, float)) and frac < claude_frac):
                        claude_frac = frac
                    if claude_reset is None or (r_sec is not None and r_sec < claude_reset):
                        claude_reset = r_sec
                else:
                    if gemini_frac is None or (isinstance(frac, (int, float)) and frac < gemini_frac):
                        gemini_frac = frac
                    if gemini_reset is None or (r_sec is not None and r_sec < gemini_reset):
                        gemini_reset = r_sec

            primary_frac = gemini_frac if gemini_frac is not None else claude_frac
            primary_reset = gemini_reset if gemini_reset is not None else claude_reset

            return {
                "quota_percent": round(primary_frac * 100) if isinstance(primary_frac, (int, float)) else None,
                "secondary_quota_percent": round(claude_frac * 100) if isinstance(claude_frac, (int, float)) else None,
                "reset_seconds": primary_reset,
                "source": "daemon_live",
            }
        except Exception:
            continue
    return None


def collect_antigravity_tokens():
    today_str = datetime.date.today().isoformat()
    base = Path.home() / ".gemini" / "antigravity" / "brain"
    input_tokens = 0
    output_tokens = 0
    if not base.exists():
        return 0, 0

    pattern = str(base / "*" / ".system_generated" / "logs" / "transcript.jsonl")
    for path in glob.glob(pattern):
        try:
            with open(path, "r", encoding="utf-8", errors="ignore") as f:
                for line in f:
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        obj = json.loads(line)
                    except Exception:
                        continue
                    if not obj.get("created_at", "").startswith(today_str):
                        continue
                    content = obj.get("content", "")
                    if isinstance(content, list):
                        content = json.dumps(content, ensure_ascii=False)
                    elif not isinstance(content, str):
                        content = str(content)
                    step_type = obj.get("type", "")
                    if step_type == "USER_INPUT":
                        input_tokens += estimate_tokens(content)
                    elif step_type == "PLANNER_RESPONSE":
                        thinking = obj.get("thinking", "") or ""
                        output_tokens += estimate_tokens(content) + estimate_tokens(thinking)
        except Exception:
            continue
    return input_tokens, output_tokens


def _parse_credit_key_ts_ms(key):
    if key.startswith("req-"):
        try:
            return int(key.split("-")[1])
        except Exception:
            return None
    if len(key) >= 12:
        try:
            return int(key[:12], 16)
        except Exception:
            return None
    return None


def collect_workbuddy_db(anchor_at_ms=None):
    db_path = Path.home() / ".workbuddy" / "workbuddy.db"
    if not db_path.exists():
        return None
    try:
        conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True, timeout=1.0)
        cur = conn.cursor()
        cur.execute(
            """
            SELECT used
            FROM session_usage
            WHERE date(updated_at / 1000, 'unixepoch', 'localtime') = date('now', 'localtime')
            """
        )
        rows = cur.fetchall()
        sessions_today = len(rows)
        total_used = sum(int(r[0]) for r in rows if isinstance(r[0], (int, float)))

        today_start_ms = int(datetime.datetime.combine(datetime.date.today(), datetime.time.min).timestamp() * 1000)
        now_ms = int(datetime.datetime.now().timestamp() * 1000) + 60000
        cur.execute("SELECT credit_json FROM session_usage WHERE credit_json IS NOT NULL")
        credits_spent_today = 0.0
        credits_spent_since_anchor = 0.0
        for (cj,) in cur.fetchall():
            try:
                cdict = json.loads(cj)
                if isinstance(cdict, dict):
                    for k, v in cdict.items():
                        ts = _parse_credit_key_ts_ms(str(k))
                        if ts is None or not isinstance(v, (int, float)):
                            continue
                        if today_start_ms <= ts <= now_ms:
                            credits_spent_today += float(v)
                        if anchor_at_ms is not None and anchor_at_ms < ts <= now_ms:
                            credits_spent_since_anchor += float(v)
            except Exception:
                pass
        conn.close()

        est_in = int(total_used * 0.7)
        est_out = max(0, total_used - est_in)
        return {
            "input_tokens": est_in,
            "output_tokens": est_out,
            "sessions_today": sessions_today,
            "credits_spent_today": round(credits_spent_today, 1),
            "credits_spent_since_anchor": round(credits_spent_since_anchor, 1),
            "source": "workbuddy_db",
        }
    except Exception:
        return None


def collect_workbuddy_checkins(anchor_at_ms=None):
    """Parse ~/.workbuddy/logs/main*.log for claimDailyCheckin success events."""
    logs_dir = Path.home() / ".workbuddy" / "logs"
    if not logs_dir.exists():
        return 0.0, 0.0

    today_start_ms = int(datetime.datetime.combine(datetime.date.today(), datetime.time.min).timestamp() * 1000)
    now_ms = int(datetime.datetime.now().timestamp() * 1000) + 60000
    seen_ts = set()
    claimed_today = 0.0
    claimed_since_anchor = 0.0

    for log_name in ("main.log", "main.old.log"):
        log_path = logs_dir / log_name
        if not log_path.exists():
            continue
        try:
            with open(log_path, "r", encoding="utf-8", errors="ignore") as f:
                for line in f:
                    if "claimDailyCheckin success" not in line:
                        continue
                    try:
                        obj = json.loads(line)
                        ts_str = obj.get("timestamp", "")
                        dt = datetime.datetime.fromisoformat(ts_str.replace("Z", "+00:00"))
                        ts_ms = int(dt.timestamp() * 1000)
                        if ts_ms in seen_ts:
                            continue
                        seen_ts.add(ts_ms)
                        msg = obj.get("message", [])
                        payload = msg[1] if isinstance(msg, list) and len(msg) > 1 and isinstance(msg[1], dict) else {}
                        credit = float(payload.get("credit", 0) or 0)
                        if today_start_ms <= ts_ms <= now_ms:
                            claimed_today += credit
                        if anchor_at_ms is not None and anchor_at_ms < ts_ms <= now_ms:
                            claimed_since_anchor += credit
                    except Exception:
                        continue
        except Exception:
            continue

    return round(claimed_today, 1), round(claimed_since_anchor, 1)


def build_status():
    cfg = load_or_create_config()
    agy_cfg = cfg.get("antigravity", {})
    wb_cfg = cfg.get("workbuddy", {})

    agy_in, agy_out = collect_antigravity_tokens()
    agy_daemon = collect_antigravity_daemon()

    agy_quota_pct = agy_daemon["quota_percent"] if agy_daemon else None
    agy_sec_pct = agy_daemon.get("secondary_quota_percent") if agy_daemon else None
    agy_reset = agy_daemon["reset_seconds"] if agy_daemon and agy_daemon["reset_seconds"] is not None else parse_iso_to_seconds(agy_cfg.get("reset_at"))

    anchor_val = wb_cfg.get("credits_anchor_value")
    anchor_at = wb_cfg.get("credits_anchor_at_ms")
    wb_db = collect_workbuddy_db(anchor_at_ms=anchor_at) or {
        "input_tokens": 0,
        "output_tokens": 0,
        "sessions_today": 0,
        "credits_spent_today": None,
        "credits_spent_since_anchor": 0.0,
        "source": "unavailable",
    }

    checkin_today, checkin_since_anchor = collect_workbuddy_checkins(anchor_at_ms=anchor_at)

    wb_rem = None
    if isinstance(anchor_val, (int, float)):
        wb_rem = round(
            max(0.0, float(anchor_val) + checkin_since_anchor - wb_db.get("credits_spent_since_anchor", 0.0)),
            1,
        )

    return {
        "locale": cfg.get("locale", "en"),
        "refresh_interval_sec": cfg.get("refresh_interval_sec", 30),
        "updated_at": datetime.datetime.now().strftime("%H:%M:%S"),
        "antigravity": {
            "name": "Antigravity",
            "connected": agy_daemon is not None,
            "input_tokens": agy_in,
            "output_tokens": agy_out,
            "credits_remaining": None,
            "quota_percent": agy_quota_pct,
            "secondary_quota_percent": agy_sec_pct,
            "credits_spent_today": None,
            "sessions_today": None,
            "reset_seconds": agy_reset,
        },
        "workbuddy": {
            "name": "WorkBuddy",
            "connected": wb_db.get("source") == "workbuddy_db",
            "input_tokens": wb_db["input_tokens"],
            "output_tokens": wb_db["output_tokens"],
            "credits_remaining": wb_rem,
            "quota_percent": None,
            "secondary_quota_percent": None,
            "credits_spent_today": wb_db.get("credits_spent_today"),
            "checkin_today": checkin_today,
            "sessions_today": wb_db.get("sessions_today"),
            "reset_seconds": parse_iso_to_seconds(wb_cfg.get("reset_at")),
        },
    }


if __name__ == "__main__":
    print(json.dumps(build_status(), ensure_ascii=False))
