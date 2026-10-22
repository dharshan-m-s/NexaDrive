use chrono::{DateTime, Utc};
use sqlx::sqlite::SqlitePool;
use std::{
    collections::HashMap,
    path::PathBuf,
    sync::{Arc, Mutex},
    time::Instant,
};
use tokio::sync::Semaphore;
use uuid::Uuid;

use crate::{config::Config, logbuf::LogBuffer, metrics::Metrics, storage_stats::StorageSummary};

#[derive(Clone)]
pub(crate) struct AppState {
    pub(crate) db: SqlitePool,
    pub(crate) storage_root: Arc<PathBuf>,
    pub(crate) instance_id: Uuid,
    pub(crate) started_at: DateTime<Utc>,
    pub(crate) login_attempts: Arc<Mutex<HashMap<String, LoginAttempt>>>,
    pub(crate) share_download_attempts: Arc<Mutex<HashMap<String, LoginAttempt>>>,
    pub(crate) public_url: Option<String>,
    pub(crate) thumb_cache: Arc<Mutex<HashMap<String, CachedThumb>>>,
    pub(crate) config: Arc<Config>,
    /// Process-wide request/latency counters and the in-memory metric series.
    pub(crate) metrics: Arc<Metrics>,
    /// Bounded ring of recent (redacted) server log lines.
    pub(crate) logs: LogBuffer,
    /// Separate throttle for dashboard sign-in attempts so console failures can
    /// never lock out the native clients' login path (or vice versa).
    pub(crate) console_attempts: Arc<Mutex<HashMap<String, LoginAttempt>>>,
    /// Short-lived cache of the whole-storage roll-up (scanning the tree on
    /// every dashboard refresh would be wasteful).
    pub(crate) storage_cache: Arc<Mutex<Option<(Instant, StorageSummary)>>>,
    /// Slots for in-flight upload streams. The server, not the client, decides
    /// how many transfers may run at once.
    pub(crate) upload_slots: Arc<Semaphore>,
    /// Short-lived cache of each user's on-disk usage, so the quota check does
    /// not re-walk the whole tree on every single upload.
    pub(crate) quota_cache: Arc<Mutex<HashMap<Uuid, QuotaCacheEntry>>>,
}

/// A cached "bytes used" reading for one account.
pub(crate) struct QuotaCacheEntry {
    /// When the walk that produced [bytes] finished.
    pub(crate) at: Instant,
    /// The `updated_at` timestamp of the walk, in SQLite's text format, so
    /// uploads that completed since then can be added back on top.
    pub(crate) cutoff: String,
    pub(crate) bytes: u64,
}

pub(crate) struct CachedThumb {
    pub(crate) generated: Instant,
    pub(crate) bytes: Vec<u8>,
}

#[derive(Clone, Copy)]
pub(crate) struct LoginAttempt {
    pub(crate) window_started: Instant,
    pub(crate) failures: u32,
}
