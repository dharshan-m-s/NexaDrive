use axum::{
    Json,
    extract::{Query, State},
    http::StatusCode,
};
use chrono::{Duration as ChronoDuration, NaiveDate, Utc};
use sqlx::Row;
use std::path::{Path, PathBuf};
use tokio::fs;
use uuid::Uuid;

use crate::{
    error::AppError,
    handlers::admin::audit,
    models::{IdQuery, StorageResponse, StorageSummaryResponse, TrashEntry},
    paths::{safe_relative_path, trash_root, user_root},
    state::AppState,
};

pub(crate) async fn list_trash(
    State(state): State<AppState>,
    axum::extract::Extension(user_id): axum::extract::Extension<Uuid>,
) -> Result<Json<Vec<TrashEntry>>, AppError> {
    let rows = sqlx::query("SELECT id, name, original_path, kind, size_bytes, deleted_at FROM trash_items WHERE user_id=$1 ORDER BY deleted_at DESC")
        .bind(user_id).fetch_all(&state.db).await?;
    let items = rows
        .into_iter()
        .map(|r| TrashEntry {
            id: r.get("id"),
            name: r.get("name"),
            original_path: r.get("original_path"),
            kind: r.get("kind"),
            size: r.get("size_bytes"),
            deleted_at: r.get("deleted_at"),
        })
        .collect();
    Ok(Json(items))
}

pub(crate) async fn restore_trash(
    State(state): State<AppState>,
    axum::extract::Extension(user_id): axum::extract::Extension<Uuid>,
    Query(query): Query<IdQuery>,
) -> Result<StatusCode, AppError> {
    let id = query
        .id
        .ok_or_else(|| AppError::BadRequest("Trash id is required".into()))?;
    let row =
        sqlx::query("SELECT original_path, trash_path FROM trash_items WHERE id=$1 AND user_id=$2")
            .bind(id)
            .bind(user_id)
            .fetch_optional(&state.db)
            .await?
            .ok_or(AppError::NotFound)?;
    let original: String = row.get("original_path");
    let trash_path: String = row.get("trash_path");
    let relative = safe_relative_path(&original)?;
    let destination = user_root(&state, user_id).join(&relative);
    if destination.exists() {
        return Err(AppError::Conflict(
            "An item already exists at the original location".into(),
        ));
    }
    if let Some(parent) = destination.parent() {
        fs::create_dir_all(parent).await?;
    }
    fs::rename(&trash_path, &destination).await?;
    sqlx::query("DELETE FROM sync_tombstones WHERE user_id=$1 AND path=$2")
        .bind(user_id)
        .bind(&original)
        .execute(&state.db)
        .await?;
    sqlx::query("DELETE FROM trash_items WHERE id=$1 AND user_id=$2")
        .bind(id)
        .bind(user_id)
        .execute(&state.db)
        .await?;
    audit(&state.db, user_id, "restore", Some(&original)).await?;
    Ok(StatusCode::NO_CONTENT)
}

pub(crate) async fn permanently_delete_trash(
    State(state): State<AppState>,
    axum::extract::Extension(user_id): axum::extract::Extension<Uuid>,
    Query(query): Query<IdQuery>,
) -> Result<StatusCode, AppError> {
    let id = query
        .id
        .ok_or_else(|| AppError::BadRequest("Trash id is required".into()))?;
    let row =
        sqlx::query("SELECT trash_path, original_path FROM trash_items WHERE id=$1 AND user_id=$2")
            .bind(id)
            .bind(user_id)
            .fetch_optional(&state.db)
            .await?
            .ok_or(AppError::NotFound)?;
    let trash_path: String = row.get("trash_path");
    let original: String = row.get("original_path");
    let candidate = PathBuf::from(&trash_path);
    let allowed_root = trash_root(&state, user_id);
    if !candidate.starts_with(&allowed_root) {
        return Err(AppError::Forbidden);
    }
    if candidate.is_dir() {
        fs::remove_dir_all(&candidate).await?;
    } else if candidate.exists() {
        fs::remove_file(&candidate).await?;
    }
    sqlx::query("DELETE FROM trash_items WHERE id=$1 AND user_id=$2")
        .bind(id)
        .bind(user_id)
        .execute(&state.db)
        .await?;
    audit(&state.db, user_id, "permanent_delete", Some(&original)).await?;
    Ok(StatusCode::NO_CONTENT)
}

pub(crate) async fn storage(
    State(state): State<AppState>,
    axum::extract::Extension(user_id): axum::extract::Extension<Uuid>,
) -> Result<Json<StorageSummaryResponse>, AppError> {
    let root = user_root(&state, user_id);
    fs::create_dir_all(&root).await?;
    let (used_bytes, file_count) = tree_stats(&root).await?;
    let quota_bytes = account_quota(&state.db, user_id).await?;
    Ok(Json(StorageSummaryResponse {
        used_bytes,
        file_count,
        quota_bytes,
    }))
}

pub(crate) async fn storage_insights(
    State(state): State<AppState>,
    axum::extract::Extension(user_id): axum::extract::Extension<Uuid>,
) -> Result<Json<StorageResponse>, AppError> {
    let root = user_root(&state, user_id);
    fs::create_dir_all(&root).await?;
    let stats = tree_insights(&root).await?;
    let quota_bytes = account_quota(&state.db, user_id).await?;
    Ok(Json(StorageResponse {
        used_bytes: stats.used_bytes,
        file_count: stats.file_count,
        quota_bytes,
        type_breakdown: stats.type_breakdown,
        activity_last_7_days: stats.activity_last_7_days,
        size_distribution: stats.size_distribution,
        largest_files: stats.largest_files,
    }))
}

/// Read the authenticated account's quota. A NULL value means unlimited.
async fn account_quota(db: &sqlx::SqlitePool, user_id: Uuid) -> Result<Option<i64>, sqlx::Error> {
    sqlx::query_scalar("SELECT quota_bytes FROM users WHERE id=$1")
        .bind(user_id)
        .fetch_one(db)
        .await
}

struct StorageTreeInsights {
    used_bytes: u64,
    file_count: u64,
    type_breakdown: Vec<crate::models::StorageTypeStat>,
    activity_last_7_days: Vec<crate::models::StorageDayStat>,
    size_distribution: Vec<crate::models::StorageSizeBand>,
    largest_files: Vec<crate::models::StorageLargestFile>,
}

fn storage_type_index(path: &Path) -> usize {
    let extension = path
        .extension()
        .and_then(|value| value.to_str())
        .unwrap_or_default()
        .to_ascii_lowercase();
    match extension.as_str() {
        "jpg" | "jpeg" | "png" | "gif" | "webp" | "heic" | "heif" | "avif" | "bmp" | "tif"
        | "tiff" | "svg" => 0,
        "mp4" | "mov" | "m4v" | "mkv" | "webm" | "avi" | "3gp" | "mpeg" | "mpg" | "ts" => 1,
        "mp3" | "m4a" | "aac" | "wav" | "flac" | "ogg" | "opus" | "wma" | "aiff" => 2,
        "pdf" | "doc" | "docx" | "xls" | "xlsx" | "ppt" | "pptx" | "txt" | "md" | "rtf" | "csv"
        | "epub" | "odt" | "ods" | "odp" => 3,
        "zip" | "7z" | "rar" | "tar" | "gz" | "bz2" | "xz" | "tgz" => 4,
        _ => 5,
    }
}

/// Builds truthful storage statistics in the same filesystem walk used for the
/// storage endpoint. No extension category or recent-activity value is guessed
/// from the root listing; all values come from actual file metadata.
async fn tree_insights(root: &Path) -> Result<StorageTreeInsights, AppError> {
    use crate::models::{StorageDayStat, StorageLargestFile, StorageSizeBand, StorageTypeStat};

    const TYPE_DEFINITIONS: [(&str, &str); 6] = [
        ("images", "Images"),
        ("videos", "Videos"),
        ("audio", "Audio"),
        ("documents", "Documents"),
        ("archives", "Archives"),
        ("other", "Other"),
    ];
    const SIZE_DEFINITIONS: [(&str, &str); 4] = [
        ("under_1mb", "Under 1 MB"),
        ("1_to_10mb", "1–10 MB"),
        ("10_to_100mb", "10–100 MB"),
        ("over_100mb", "100 MB and above"),
    ];

    let mut type_breakdown: Vec<StorageTypeStat> = TYPE_DEFINITIONS
        .iter()
        .map(|(key, label)| StorageTypeStat {
            key: (*key).to_string(),
            label: (*label).to_string(),
            bytes: 0,
            count: 0,
        })
        .collect();
    let mut size_distribution: Vec<StorageSizeBand> = SIZE_DEFINITIONS
        .iter()
        .map(|(key, label)| StorageSizeBand {
            key: (*key).to_string(),
            label: (*label).to_string(),
            count: 0,
            bytes: 0,
        })
        .collect();

    let today = Utc::now().date_naive();
    let first_day = today - ChronoDuration::days(6);
    let mut activity_last_7_days: Vec<StorageDayStat> = (0..7)
        .map(|offset| {
            let date: NaiveDate = first_day + ChronoDuration::days(offset);
            StorageDayStat {
                date: date.format("%Y-%m-%d").to_string(),
                label: date.format("%a").to_string(),
                bytes: 0,
                count: 0,
            }
        })
        .collect();

    let mut stack = vec![root.to_path_buf()];
    let mut used_bytes = 0u64;
    let mut file_count = 0u64;
    let mut largest_files: Vec<StorageLargestFile> = Vec::with_capacity(5);

    while let Some(dir) = stack.pop() {
        let mut entries = match fs::read_dir(dir).await {
            Ok(entries) => entries,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => continue,
            Err(error) => return Err(AppError::Io(error)),
        };
        while let Some(entry) = entries.next_entry().await? {
            let file_type = match entry.file_type().await {
                Ok(file_type) => file_type,
                Err(error) if error.kind() == std::io::ErrorKind::NotFound => continue,
                Err(error) => return Err(AppError::Io(error)),
            };
            if file_type.is_symlink() {
                continue;
            }
            if file_type.is_dir() {
                stack.push(entry.path());
                continue;
            }
            if !file_type.is_file() {
                continue;
            }

            let name = entry.file_name().to_string_lossy().to_string();
            if crate::handlers::upload::is_staging_name(&name) {
                continue;
            }
            let metadata = match entry.metadata().await {
                Ok(metadata) => metadata,
                Err(error) if error.kind() == std::io::ErrorKind::NotFound => continue,
                Err(error) => return Err(AppError::Io(error)),
            };

            let size = metadata.len();
            used_bytes = used_bytes.saturating_add(size);
            file_count = file_count.saturating_add(1);

            let type_index = storage_type_index(&entry.path());
            type_breakdown[type_index].bytes =
                type_breakdown[type_index].bytes.saturating_add(size);
            type_breakdown[type_index].count = type_breakdown[type_index].count.saturating_add(1);

            let size_index = if size < 1_048_576 {
                0
            } else if size < 10_485_760 {
                1
            } else if size < 104_857_600 {
                2
            } else {
                3
            };
            size_distribution[size_index].bytes =
                size_distribution[size_index].bytes.saturating_add(size);
            size_distribution[size_index].count =
                size_distribution[size_index].count.saturating_add(1);

            let modified_at = metadata.modified().ok().map(chrono::DateTime::<Utc>::from);
            if let Some(modified) = modified_at.as_ref() {
                let day_offset = modified
                    .date_naive()
                    .signed_duration_since(first_day)
                    .num_days();
                if (0..7).contains(&day_offset) {
                    let day = &mut activity_last_7_days[day_offset as usize];
                    day.bytes = day.bytes.saturating_add(size);
                    day.count = day.count.saturating_add(1);
                }
            }

            if size > 0 {
                let relative = entry
                    .path()
                    .strip_prefix(root)
                    .map_err(|_| AppError::Internal)?
                    .to_string_lossy()
                    .replace('\\', "/");
                let candidate = StorageLargestFile {
                    name: name.clone(),
                    path: relative,
                    size_bytes: size,
                    modified_at,
                };
                if largest_files.len() < 5 {
                    largest_files.push(candidate);
                } else if let Some((smallest_index, smallest)) = largest_files
                    .iter()
                    .enumerate()
                    .min_by_key(|(_, item)| item.size_bytes)
                    && size > smallest.size_bytes
                {
                    largest_files[smallest_index] = candidate;
                }
            }
        }
    }

    largest_files.sort_by_key(|file| std::cmp::Reverse(file.size_bytes));

    Ok(StorageTreeInsights {
        used_bytes,
        file_count,
        type_breakdown,
        activity_last_7_days,
        size_distribution,
        largest_files,
    })
}

pub(crate) async fn folder_size(path: &Path) -> Result<u64, AppError> {
    Ok(tree_stats(path).await?.0)
}

pub(crate) async fn tree_stats(root: &Path) -> Result<(u64, u64), AppError> {
    let mut stack = vec![root.to_path_buf()];
    let mut used = 0u64;
    let mut count = 0u64;
    while let Some(dir) = stack.pop() {
        // The tree changes underneath a walk (files are uploaded, renamed or
        // deleted while it runs), so a directory that disappears mid-walk is
        // not an error: it simply contributes nothing.
        let mut entries = match fs::read_dir(dir).await {
            Ok(entries) => entries,
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => continue,
            Err(e) => return Err(AppError::Io(e)),
        };
        while let Some(entry) = entries.next_entry().await? {
            let ft = match entry.file_type().await {
                Ok(ft) => ft,
                Err(e) if e.kind() == std::io::ErrorKind::NotFound => continue,
                Err(e) => return Err(AppError::Io(e)),
            };
            if ft.is_symlink() {
                continue;
            }
            if ft.is_dir() {
                stack.push(entry.path());
            } else if ft.is_file() {
                let name = entry.file_name().to_string_lossy().to_string();
                // Partially uploaded files are not user data yet.
                if crate::handlers::upload::is_staging_name(&name) {
                    continue;
                }
                let metadata = match entry.metadata().await {
                    Ok(metadata) => metadata,
                    Err(e) if e.kind() == std::io::ErrorKind::NotFound => continue,
                    Err(e) => return Err(AppError::Io(e)),
                };
                used = used.saturating_add(metadata.len());
                count += 1;
            }
        }
    }
    Ok((used, count))
}

#[cfg(test)]
mod tests {
    use super::*;
    use sqlx::sqlite::SqlitePoolOptions;

    #[tokio::test]
    async fn storage_insights_use_real_file_sizes_types_and_modified_dates() {
        let root =
            std::env::temp_dir().join(format!("nexadrive-storage-insights-{}", Uuid::new_v4()));
        fs::create_dir_all(&root).await.unwrap();

        fs::write(root.join("photo.jpg"), vec![1_u8; 128])
            .await
            .unwrap();
        fs::write(root.join("clip.mp4"), vec![2_u8; 2 * 1_048_576])
            .await
            .unwrap();
        fs::write(root.join("backup.zip"), vec![3_u8; 11 * 1_048_576])
            .await
            .unwrap();

        let stats = tree_insights(&root).await.unwrap();
        assert_eq!(stats.file_count, 3);
        assert_eq!(stats.type_breakdown[0].count, 1);
        assert_eq!(stats.type_breakdown[0].bytes, 128);
        assert_eq!(stats.type_breakdown[1].count, 1);
        assert_eq!(stats.type_breakdown[2].count, 0);
        assert_eq!(stats.type_breakdown[4].count, 1);
        assert_eq!(stats.size_distribution[0].count, 1);
        assert_eq!(stats.size_distribution[1].count, 1);
        assert_eq!(stats.size_distribution[2].count, 1);
        assert_eq!(stats.largest_files.first().unwrap().name, "backup.zip");
        assert_eq!(
            stats
                .activity_last_7_days
                .iter()
                .map(|day| day.count)
                .sum::<u64>(),
            3
        );
        assert_eq!(
            stats
                .type_breakdown
                .iter()
                .map(|entry| entry.bytes)
                .sum::<u64>(),
            stats.used_bytes
        );

        fs::remove_dir_all(&root).await.unwrap();
    }

    #[tokio::test]
    async fn storage_quota_is_read_from_the_authenticated_account() {
        let db = SqlitePoolOptions::new()
            .max_connections(1)
            .connect("sqlite::memory:")
            .await
            .unwrap();
        sqlx::query("CREATE TABLE users (id BLOB PRIMARY KEY, quota_bytes BIGINT)")
            .execute(&db)
            .await
            .unwrap();

        let metered_user = Uuid::new_v4();
        let unlimited_user = Uuid::new_v4();
        sqlx::query("INSERT INTO users (id, quota_bytes) VALUES ($1, $2)")
            .bind(metered_user)
            .bind(5_000_i64)
            .execute(&db)
            .await
            .unwrap();
        sqlx::query("INSERT INTO users (id, quota_bytes) VALUES ($1, NULL)")
            .bind(unlimited_user)
            .execute(&db)
            .await
            .unwrap();

        assert_eq!(account_quota(&db, metered_user).await.unwrap(), Some(5_000));
        assert_eq!(account_quota(&db, unlimited_user).await.unwrap(), None);
    }
}
