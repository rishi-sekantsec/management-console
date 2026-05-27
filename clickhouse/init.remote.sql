CREATE DATABASE IF NOT EXISTS sekant;

CREATE TABLE IF NOT EXISTS sekant.security_events
(
    -- ── Core fields ──────────────────────────────────────────────────────────
    schema                  UInt8,
    event_utc_ms            DateTime64(3, 'UTC'),
    browser_uuid            String,
    event_uuid              UUID,
    event_type              LowCardinality(String),

    -- ── Basic info ───────────────────────────────────────────────────────────
    tab_url                 Nullable(String)                 DEFAULT NULL,
    tab_id                  Int32                            DEFAULT -1,
    hostname                LowCardinality(Nullable(String)) DEFAULT NULL,
    frame_url               Nullable(String)                 DEFAULT NULL,
    event_source            LowCardinality(Nullable(String)) DEFAULT NULL,
    -- Composite session key: hash of (browser_uuid, tab_id, tab_url). Groups events from the same browser + tab + page.
    -- MATERIALIZED: computed at insert time from browser_uuid + tab_id + tab_url. Never present in the JSON wire format.
    session_id              UInt64 MATERIALIZED cityHash64(concat(browser_uuid, toString(tab_id), ifNull(tab_url, ''))),
    -- Opaque blob — no sub-paths indexed. Known field: download_id (DOWNLOAD).
    -- Access via JSONExtractInt(metadata, 'download_id'), etc. See event_source for hook/upload source.
    metadata                JSON(max_dynamic_types=0, max_dynamic_paths=0),

    -- ── Browser context ──────────────────────────────────────────────────────
    browser_name                         LowCardinality(Nullable(String)) DEFAULT NULL,
    browser_version                      Nullable(String)                 DEFAULT NULL,
    browser_os                           LowCardinality(Nullable(String)) DEFAULT NULL,
    browser_os_version                   Nullable(String)                 DEFAULT NULL,
    browser_extension_version            Nullable(String)                 DEFAULT NULL,
    browser_vulnerability_count          Nullable(UInt32)                 DEFAULT NULL,
    browser_vulnerability_checked_utc_ms Nullable(Int64)                  DEFAULT NULL,

    -- ── Event context ────────────────────────────────────────────────────────
    ctx_reputation          LowCardinality(Nullable(String)) DEFAULT NULL,
    ctx_organization        Nullable(String)       DEFAULT NULL,
    ctx_is_new_domain       Nullable(Bool)         DEFAULT NULL,
    ctx_url_context         LowCardinality(Nullable(String)) DEFAULT NULL,
    ctx_ip                  Nullable(String)       DEFAULT NULL,
    ctx_referrer            Nullable(String)       DEFAULT NULL,
    ctx_referred_by_search  Nullable(Bool) DEFAULT NULL,
    ctx_considered_ai_site  Nullable(Bool) DEFAULT NULL,
    ctx_considered_hosting_site Nullable(Bool) DEFAULT NULL,
    ctx_unfamiliar_domain       Nullable(Bool) DEFAULT NULL,
    ctx_page_title              Nullable(String) DEFAULT NULL,

    -- ── Risk fields ──────────────────────────────────────────────────────────
    risk_type               LowCardinality(Nullable(String)) DEFAULT NULL,
    risk_level              LowCardinality(Nullable(String)) DEFAULT NULL,
    risk_rationale          Nullable(String)       DEFAULT NULL,
    -- Opaque blob — no sub-paths indexed. Shape varies by risk_type.
    -- Access via JSONExtract*() functions.
    risk_context            JSON(max_dynamic_types=0, max_dynamic_paths=0),

    -- ── Verdicts ─────────────────────────────────────────────────────────────
    verdicts                Array(Tuple(
        type                LowCardinality(String),
        verdict             LowCardinality(String),
        reason              String
    )),

    -- ── Action fields ────────────────────────────────────────────────────────
    action                  LowCardinality(Nullable(String)) DEFAULT NULL,
    secondary_url           Nullable(String)       DEFAULT NULL,

    -- ── v2: Intercept matches ───────────────────────────────────────────────
    -- Shape mirrors YARA output. `metadata` is stored as a raw JSON String
    -- because the JSON type is not supported inside Array(Tuple).
    -- metadata String values expected ≤ 10 KB.
    intercept_matches       Array(Tuple(
        rule_name           String,
        namespace           String,
        tags                Array(String),
        metadata            String,
        match_strings       Array(Tuple(string_name String, count UInt32))
    )),

    -- ── v2: Intercept context (Intercept.js / YARA engine) ──────────────────
    -- Schema TBD. Stored as an opaque JSON blob with all inference disabled
    -- (max_dynamic_types=0, max_dynamic_paths=0) so no sub-paths are indexed
    -- or flattened. Use JSONExtract*() functions for runtime access.
    intercept_context       JSON(max_dynamic_types=0, max_dynamic_paths=0),

    -- ── v2: Files ────────────────────────────────────────────────────────────
    files                   Array(Tuple(
        name                String,
        size                Int64,
        mime                LowCardinality(String),
        hash_sha256         Nullable(String)
    )),

    -- ── v2: Content ──────────────────────────────────────────────────────────
    -- content_snippet is truncated to 10,000 characters by the caller (enforced by addContent()).
    content_snippet         Nullable(String)       DEFAULT NULL CODEC(ZSTD(1)),
    content_length          Nullable(Int64)        DEFAULT NULL,

    -- ── v2: User gesture ─────────────────────────────────────────────────────
    user_gesture            LowCardinality(Nullable(String)) DEFAULT NULL,
    user_gesture_utc_ms     Nullable(Int64)        DEFAULT NULL,

    -- ── v2: Indicators ───────────────────────────────────────────────────────
    indicators              Array(Tuple(
        type                LowCardinality(String),
        value               String,
        url                 Nullable(String),
        resource            LowCardinality(Nullable(String))
    )),

    -- ── v2: MITRE ATT&CK threats ─────────────────────────────────────────────
    -- evidence String values expected ≤ 10 KB.
    threats                 Array(Tuple(
        tactic              LowCardinality(Nullable(String)),
        technique           LowCardinality(String),
        description         Nullable(String),
        evidence            Nullable(String),
        severity            LowCardinality(String)
    )),

    -- ── v2: Script attribution ───────────────────────────────────────────────
    -- Stored as a single JSON column. All current fields are typed below;
    -- JSON retained so future identity fields land without a schema migration.
    script_attribution      JSON(
        name                String,
        callsite            String,
        url                 String,
        first_party         Nullable(Bool)
    ),

    -- ── Ingestion metadata ───────────────────────────────────────────────────
    _ingest_time_utc_ms     DateTime64(3, 'UTC') DEFAULT now64(),
    INDEX idx_event_uuid event_uuid TYPE bloom_filter(0.01) GRANULARITY 1
)
ENGINE = MergeTree()
PARTITION BY toMonday(event_utc_ms)
ORDER BY (event_utc_ms, event_type, browser_uuid)
SETTINGS index_granularity = 8192, storage_policy = 's3';

CREATE TABLE IF NOT EXISTS sekant.rules_hit (
  rule_id UUID,
  hit_timestamp DateTime64(3, 'UTC') DEFAULT now64(),
  event_id Nullable(String),
  event_type LowCardinality(Nullable(String)),
  risk_type LowCardinality(Nullable(String)),
  risk_level LowCardinality(Nullable(String)),
  risk_ratinlae Nullable(String),
  action LowCardinality(Nullable(String)),
  hostname Nullable(String),
  browser_type LowCardinality(Nullable(String)),
  os LowCardinality(Nullable(String)),
  query_result_json String,
  _processed UInt8 DEFAULT 0,
  INDEX idx_processed _processed TYPE set(0) GRANULARITY 64
)
ENGINE = MergeTree()
ORDER BY (rule_id, hit_timestamp)
SETTINGS storage_policy = 's3';

CREATE TABLE IF NOT EXISTS sekant.audit_logs (
  id UUID DEFAULT generateUUIDv4(),
  timestamp DateTime64(3) DEFAULT now64(),
  actor_id String,
  actor_ip String,
  action LowCardinality(String),
  target_id String DEFAULT '',
  details String DEFAULT '{}',
  description String DEFAULT ''
)
ENGINE = MergeTree
ORDER BY (timestamp, actor_id, action)
SETTINGS storage_policy = 's3';
