use chrono::{DateTime, Utc};
use serde::Serialize;
use sqlx::Row;
use uuid::Uuid;

use crate::{
    error::AppError,
    handlers::storage::tree_stats,
    paths::{trash_root, user_root},
    state::AppState,
};

/// Per-account storage footprint on disk. Derived by walking the real user
/// directory, never from client-reported values.
#[derive(Clone, Serialize)]
pub(crate) struct UserStorage {
    pub(crate) user_id: Uuid,
    pub(crate) username: String,
    pub(crate) disabled: bool,
    pub(crate) bytes: u64,
    pub(crate) files: u64,
    pub(crate) quota_bytes: Option<i64>,
}

/// Whole-instance storage roll-up across every account.
#[derive(Clone, Serialize)]
pub(crate) struct StorageSummary {
    pub(crate) total_bytes: u64,
    pub(crate) total_files: u64,
    pub(crate) trash_bytes: u64,
    pub(crate) users: Vec<UserStorage>,
    pub(crate) scanned_at: DateTime<Utc>,
}

/// Walks every account's storage root once. This is the expensive operation
/// that callers cache; it deliberately reuses the same `tree_stats` walk the
/// per-user `/api/storage` endpoint uses so the numbers agree.
pub(crate) async fn scan(state: &AppState) -> Result<StorageSummary, AppError> {
    let rows =
        sqlx::query("SELECT id, username, disabled, quota_bytes FROM users ORDER BY username")
            .fetch_all(&state.db)
            .await?;

    let mut users = Vec::with_capacity(rows.len());
    let mut total_bytes = 0u64;
    let mut total_files = 0u64;
    let mut total_trash_bytes = 0u64;

    for row in rows {
        let user_id: Uuid = row.get("id");
        let root = user_root(state, user_id);
        let (bytes, files) = if tokio::fs::try_exists(&root).await.unwrap_or(false) {
            tree_stats(&root).await.unwrap_or((0, 0))
        } else {
            (0, 0)
        };
        let trash = trash_root(state, user_id);
        let trash_bytes = if tokio::fs::try_exists(&trash).await.unwrap_or(false) {
            tree_stats(&trash).await.map(|(b, _)| b).unwrap_or(0)
        } else {
            0
        };
        total_bytes = total_bytes.saturating_add(bytes);
        total_files = total_files.saturating_add(files);
        total_trash_bytes = total_trash_bytes.saturating_add(trash_bytes);
        users.push(UserStorage {
            user_id,
            username: row.get("username"),
            disabled: row.get("disabled"),
            bytes,
            files,
            quota_bytes: row.get("quota_bytes"),
        });
    }

    Ok(StorageSummary {
        total_bytes,
        total_files,
        trash_bytes: total_trash_bytes,
        users,
        scanned_at: Utc::now(),
    })
}

/// Returns a cached summary when it is younger than `ttl_secs`, otherwise
/// rescans. The cache lock is never held across an await.
pub(crate) async fn cached(state: &AppState, ttl_secs: u64) -> Result<StorageSummary, AppError> {
    {
        let guard = state.storage_cache.lock().map_err(|_| AppError::Internal)?;
        if let Some((at, summary)) = guard.as_ref()
            && at.elapsed().as_secs() < ttl_secs
        {
            return Ok(summary.clone());
        }
    }
    let summary = scan(state).await?;
    if let Ok(mut guard) = state.storage_cache.lock() {
        *guard = Some((std::time::Instant::now(), summary.clone()));
    }
    Ok(summary)
}
