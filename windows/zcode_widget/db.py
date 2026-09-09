"""Read-only access to ZCode's token usage DB (port of Database.swift +
TokenUsageRepository.swift + Models.swift).

Opened in SQLite read-only/URI mode so the widget can never lock or
corrupt the DB while ZCode is running. `started_at` is INTEGER
milliseconds since the Unix epoch (not ISO strings).

Token semantics (verified against raw_usage_json):
  - input_tokens INCLUDES cache reads + cache writes
  - fresh input = input_tokens - cache_read - cache_creation
  - computed_total_tokens = input_tokens + output_tokens
The UI and Sheets export therefore report *fresh* input everywhere and
label totals as including cache.
"""

from __future__ import annotations

import sqlite3
import time
import urllib.parse
from dataclasses import dataclass
from datetime import datetime

from . import paths


def _connect() -> sqlite3.Connection:
    uri = "file:" + urllib.parse.quote(paths.DB_PATH.as_posix()) + "?mode=ro"
    conn = sqlite3.connect(uri, uri=True, timeout=2.0)
    conn.row_factory = sqlite3.Row
    return conn


def _query(sql: str, args: tuple = (), fetch: str = "all"):
    if not paths.DB_PATH.exists():
        raise DbUnavailable(f"Database not found at {paths.DB_PATH}")
    try:
        conn = _connect()
    except sqlite3.Error as e:
        raise DbUnavailable(str(e)) from e
    try:
        cur = conn.execute(sql, args)
        return cur.fetchall() if fetch == "all" else cur.fetchone()
    finally:
        conn.close()


class DbUnavailable(Exception):
    pass


def today_start_ms() -> int:
    """Local midnight — everything at/after this is 'today' and volatile."""
    now = datetime.now()
    return int(datetime(now.year, now.month, now.day).timestamp() * 1000)


# -- aggregates --------------------------------------------------------

FRESH_IN = "SUM(input_tokens - COALESCE(cache_read_input_tokens, 0) - COALESCE(cache_creation_input_tokens, 0))"


@dataclass
class UsageTotals:
    input_fresh: int = 0   # excludes cached tokens
    cached: int = 0        # cache reads + writes
    total_output: int = 0
    total_computed: int = 0  # includes cache
    call_count: int = 0


@dataclass
class DailyUsage:
    day: str  # "yyyy-MM-dd"
    input_tokens: int      # fresh, excludes cache
    output_tokens: int
    computed_total: int    # includes cache
    turns: int = 0
    cached: int = 0        # cache reads + writes


@dataclass
class MonthlyUsage:
    month: str  # "yyyy-MM"
    input_tokens: int
    output_tokens: int
    computed_total: int
    turns: int = 0


@dataclass
class SessionUsage:
    session_id: str
    title: str
    turns: int
    input_tokens: int      # fresh, excludes cache
    output_tokens: int
    computed_total: int    # includes cache
    cached: int = 0        # cache reads + writes
    models: str = ""       # comma-joined distinct model ids used
    first_ms: int = 0      # first turn started (first message sent)
    last_ms: int = 0       # last turn completed (last message sent)

    @property
    def title_or_id(self) -> str:
        return self.title or self.session_id

    @property
    def cached_pct(self) -> float:
        denom = self.input_tokens + self.cached
        return (self.cached / denom * 100) if denom else 0.0


@dataclass
class ModelDayUsage:
    day: str       # "yyyy-MM-dd"
    model: str
    calls: int
    input_tokens: int   # fresh
    output_tokens: int
    computed_total: int


@dataclass
class ModelTotals:
    model: str
    calls: int
    input_tokens: int   # fresh
    output_tokens: int
    cached: int
    computed_total: int

    @property
    def cached_pct(self) -> float:
        denom = self.input_tokens + self.cached
        return (self.cached / denom * 100) if denom else 0.0


def totals(today_only: bool = False) -> UsageTotals:
    where, args = "", ()
    if today_only:
        where = "WHERE started_at >= ?"
        args = (today_start_ms(),)
    row = _query(
        f"""
        SELECT {FRESH_IN} AS ti,
               COALESCE(SUM(COALESCE(cache_read_input_tokens, 0)
                          + COALESCE(cache_creation_input_tokens, 0)), 0) AS tc,
               COALESCE(SUM(output_tokens), 0) AS to_,
               COALESCE(SUM(computed_total_tokens), 0) AS tt,
               COUNT(*) AS n
        FROM turn_usage
        {where}
        """,
        args,
        fetch="one",
    )
    return UsageTotals(row["ti"] or 0, row["tc"] or 0, row["to_"] or 0,
                       row["tt"] or 0, row["n"] or 0)


def daily_totals(days: int | None = 7, include_today: bool = True) -> list[DailyUsage]:
    """Daily aggregates, oldest first. days=None = full history."""
    where, args = [], []
    if days is not None:
        where.append("started_at >= ?")
        args.append(int((time.time() - days * 86400) * 1000))
    if not include_today:
        where.append("started_at < ?")
        args.append(today_start_ms())
    clause = ("WHERE " + " AND ".join(where)) if where else ""
    rows = _query(
        f"""
        SELECT date(started_at / 1000, 'unixepoch') AS day,
               {FRESH_IN} AS input_tokens,
               COALESCE(SUM(output_tokens), 0) AS output_tokens,
               COALESCE(SUM(computed_total_tokens), 0) AS computed_total,
               COUNT(*) AS turns,
               COALESCE(SUM(COALESCE(cache_read_input_tokens, 0)
                          + COALESCE(cache_creation_input_tokens, 0)), 0) AS cached
        FROM turn_usage
        {clause}
        GROUP BY day
        ORDER BY day ASC
        """,
        tuple(args),
    )
    return [
        DailyUsage(r["day"], r["input_tokens"] or 0, r["output_tokens"] or 0,
                   r["computed_total"] or 0, r["turns"] or 0, r["cached"] or 0)
        for r in rows
        if r["day"] is not None
    ]


def hourly_today() -> list[DailyUsage]:
    """Per-hour aggregates for today (local time), hours 0..now.

    Bucketed in Python from raw timestamps so hours are local, not UTC.
    """
    rows = _query(
        f"""
        SELECT started_at,
               input_tokens - COALESCE(cache_read_input_tokens, 0)
                             - COALESCE(cache_creation_input_tokens, 0) AS fresh_in,
               COALESCE(output_tokens, 0) AS out_tok
        FROM turn_usage
        WHERE started_at >= ?
        ORDER BY started_at ASC
        """,
        (today_start_ms(),),
    )
    buckets: dict[int, DailyUsage] = {}
    now_dt = datetime.now()
    for r in rows:
        dt = datetime.fromtimestamp(r["started_at"] / 1000)
        if dt.date() != now_dt.date():
            continue
        h = dt.hour
        b = buckets.setdefault(h, DailyUsage(f"{h:02d}:00", 0, 0, 0, 0))
        b.input_tokens += r["fresh_in"] or 0
        b.output_tokens += r["out_tok"] or 0
        b.turns += 1
        b.computed_total += (r["fresh_in"] or 0) + (r["out_tok"] or 0)
    return [buckets[h] for h in sorted(buckets)]


def monthly_totals(months: int = 12) -> list[MonthlyUsage]:
    """Per-calendar-month aggregates, oldest first (last `months` months)."""
    rows = _query(
        f"""
        SELECT strftime('%Y-%m', started_at / 1000, 'unixepoch') AS month,
               {FRESH_IN} AS input_tokens,
               COALESCE(SUM(output_tokens), 0) AS output_tokens,
               COALESCE(SUM(computed_total_tokens), 0) AS computed_total,
               COUNT(*) AS turns
        FROM turn_usage
        GROUP BY month
        ORDER BY month ASC
        """
    )
    out = [
        MonthlyUsage(r["month"], r["input_tokens"] or 0, r["output_tokens"] or 0,
                     r["computed_total"] or 0, r["turns"] or 0)
        for r in rows
        if r["month"] is not None
    ]
    return out[-months:]


def recent_turns(limit: int = 20, today_only: bool = False) -> list[dict]:
    """Last N turns, newest first (list display order)."""
    where, args = "", []
    if today_only:
        where = "WHERE started_at >= ?"
        args.append(today_start_ms())
    rows = _query(
        f"""
        SELECT status, started_at, input_tokens, output_tokens,
               cache_read_input_tokens, cache_creation_input_tokens,
               model_request_count, tool_call_count, duration_ms,
               session_id, turn_id
        FROM turn_usage
        {where}
        ORDER BY started_at DESC
        LIMIT ?
        """,
        tuple(args) + (limit,),
    )
    return [
        {
            "status": r["status"] or "",
            "started_at": r["started_at"] or 0,
            "input": (r["input_tokens"] or 0)
                     - (r["cache_read_input_tokens"] or 0)
                     - (r["cache_creation_input_tokens"] or 0),
            "output": r["output_tokens"] or 0,
            "requests": r["model_request_count"] or 0,
            "tools": r["tool_call_count"] or 0,
            "duration_ms": r["duration_ms"] or 0,
            "session_id": r["session_id"] or "",
            "turn_id": r["turn_id"] or "",
        }
        for r in rows
    ]


def session_summaries(exclude_today: bool = False) -> list[SessionUsage]:
    """One row per session with title, message timings and token counts.

    first_ms = first turn start (first message sent),
    last_ms  = last turn completion (last message sent).
    Sorted newest-first. With exclude_today=True, sessions whose latest
    activity is today are omitted (their numbers are still moving).
    """
    where = ""
    args: tuple = ()
    if exclude_today:
        where = "MAX(COALESCE(t.completed_at, t.started_at)) < ?"
        args = (today_start_ms(),)
    having = f"HAVING {where}" if where else ""
    rows = _query(
        f"""
        SELECT s.id, COALESCE(s.title, '') AS title,
               COUNT(t.turn_id) AS turns,
               {FRESH_IN} AS input_tokens,
               COALESCE(SUM(t.output_tokens), 0) AS output_tokens,
               COALESCE(SUM(t.computed_total_tokens), 0) AS computed_total,
               COALESCE(SUM(COALESCE(t.cache_read_input_tokens, 0)
                          + COALESCE(t.cache_creation_input_tokens, 0)), 0) AS cached,
               MIN(t.started_at) AS first_ms,
               MAX(COALESCE(t.completed_at, t.started_at)) AS last_ms
        FROM session s
        JOIN turn_usage t ON t.session_id = s.id
        GROUP BY s.id
        {having}
        ORDER BY first_ms DESC
        """,
        args,
    )
    # distinct models per session live in model_usage, not turn_usage
    models_by_session: dict[str, str] = {}
    for m in _query(
        """
        SELECT session_id, GROUP_CONCAT(DISTINCT model_id) AS models
        FROM model_usage
        GROUP BY session_id
        """
    ):
        models_by_session[m["session_id"]] = m["models"] or ""
    return [
        SessionUsage(
            session_id=r["id"],
            title=r["title"],
            turns=r["turns"] or 0,
            input_tokens=r["input_tokens"] or 0,
            output_tokens=r["output_tokens"] or 0,
            computed_total=r["computed_total"] or 0,
            cached=r["cached"] or 0,
            models=models_by_session.get(r["id"], ""),
            first_ms=r["first_ms"] or 0,
            last_ms=r["last_ms"] or 0,
        )
        for r in rows
    ]


def daily_model_usage(days: int | None = 30, include_today: bool = True) -> list[ModelDayUsage]:
    """Per-day per-model token aggregates (model_usage rows), newest day first."""
    where, args = [], []
    if days is not None:
        where.append("started_at >= ?")
        args.append(int((time.time() - days * 86400) * 1000))
    if not include_today:
        where.append("started_at < ?")
        args.append(today_start_ms())
    clause = ("WHERE " + " AND ".join(where)) if where else ""
    rows = _query(
        f"""
        SELECT date(started_at / 1000, 'unixepoch') AS day,
               model_id,
               COUNT(*) AS calls,
               SUM(input_tokens - COALESCE(cache_read_input_tokens, 0)
                              - COALESCE(cache_creation_input_tokens, 0)) AS fresh_in,
               COALESCE(SUM(output_tokens), 0) AS out_tok,
               COALESCE(SUM(computed_total_tokens), 0) AS total
        FROM model_usage
        {clause}
        GROUP BY day, model_id
        ORDER BY day DESC, total DESC
        """,
        tuple(args),
    )
    return [
        ModelDayUsage(r["day"], r["model_id"], r["calls"],
                      r["fresh_in"] or 0, r["out_tok"] or 0, r["total"] or 0)
        for r in rows
        if r["day"] is not None
    ]


def model_totals() -> list[ModelTotals]:
    """All-time per-model aggregates, biggest consumers first."""
    rows = _query(
        """
        SELECT model_id,
               COUNT(*) AS calls,
               SUM(input_tokens - COALESCE(cache_read_input_tokens, 0)
                              - COALESCE(cache_creation_input_tokens, 0)) AS fresh_in,
               COALESCE(SUM(output_tokens), 0) AS out_tok,
               COALESCE(SUM(COALESCE(cache_read_input_tokens, 0)
                          + COALESCE(cache_creation_input_tokens, 0)), 0) AS cached,
               COALESCE(SUM(computed_total_tokens), 0) AS total
        FROM model_usage
        GROUP BY model_id
        ORDER BY total DESC
        """
    )
    return [
        ModelTotals(r["model_id"], r["calls"], r["fresh_in"] or 0,
                    r["out_tok"] or 0, r["cached"] or 0, r["total"] or 0)
        for r in rows
    ]


def format_tokens(n: int) -> str:
    """Compact token formatting."""
    if n >= 1_000_000:
        v = n / 1_000_000
        return f"{v:.1f}M".replace(".0M", "M")
    if n >= 1_000:
        v = n / 1_000
        return f"{v:.1f}k".replace(".0k", "k")
    return str(n)


def format_ms(ms: int, fmt: str = "%m-%d %H:%M") -> str:
    return datetime.fromtimestamp(ms / 1000).strftime(fmt)
