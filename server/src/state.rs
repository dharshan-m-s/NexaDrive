use chrono::{DateTime, Utc};
use sqlx::sqlite::SqlitePool;
use std::{
    collections::HashMap,
    path::PathBuf,
    sync::{Arc, Mutex},
    time::Instant,
};
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
