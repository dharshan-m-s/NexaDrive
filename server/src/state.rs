use chrono::{DateTime, Utc};
use sqlx::sqlite::SqlitePool;
use std::{
    collections::HashMap,
    path::PathBuf,
    sync::{Arc, Mutex},
    time::Instant,
};
use uuid::Uuid;

use crate::config::Config;

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
