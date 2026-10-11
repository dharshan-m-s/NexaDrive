use axum::{Json, extract::State};
use chrono::{DateTime, Utc};
use tokio::{fs, process::Command};
use uuid::Uuid;

use crate::{
    auth::require_admin,
    error::AppError,
    handlers::{admin::audit, notifications::create_notification},
    models::{
        BackupCheckResponse, BackupRestoreRequest, BackupRunRequest, BackupRunResponse,
        BackupSnapshotResponse, BackupStatusResponse,
    },
    state::AppState,
};

pub(crate) async fn backup_status(
    State(state): State<AppState>,
    axum::extract::Extension(user_id): axum::extract::Extension<Uuid>,
) -> Result<Json<BackupStatusResponse>, AppError> {
    require_admin(&state.db, user_id).await?;
    let repository = state.config.restic_repository.clone();
    let configured = repository.is_some() && state.config.restic_password_file.is_some();
    let bin = state.config.restic_bin.clone();
    let available = Command::new(&bin)
        .arg("version")
        .output()
        .await
        .map(|o| o.status.success())
        .unwrap_or(false);
    Ok(Json(BackupStatusResponse {
        configured,
        restic_available: available,
        repository,
    }))
}

pub(crate) async fn backup_run(
    State(state): State<AppState>,
    axum::extract::Extension(user_id): axum::extract::Extension<Uuid>,
    Json(payload): Json<BackupRunRequest>,
) -> Result<Json<BackupRunResponse>, AppError> {
    require_admin(&state.db, user_id).await?;
    let repository = state
        .config
        .restic_repository
        .clone()
        .ok_or_else(|| AppError::BadRequest("RESTIC_REPOSITORY is not configured".into()))?;
    if state.config.restic_password_file.is_none() {
        return Err(AppError::BadRequest(
            "RESTIC_PASSWORD_FILE is not configured".into(),
        ));
    }
    let bin = state.config.restic_bin.clone();
    let storage = state.storage_root.to_string_lossy().to_string();
    let trash = state
        .storage_root
        .join(".trash")
        .to_string_lossy()
        .to_string();
    // SQLite is a live database. Create a transactionally consistent snapshot before
    // Restic reads it so the backup contains both files and metadata.
    let db_snapshot = state
        .storage_root
        .join(format!(".nexadrive-db-backup-{}.db", Uuid::new_v4()));
    let escaped_snapshot = db_snapshot.to_string_lossy().replace('\'', "''");
    // `VACUUM INTO` takes a filename expression, not a bind parameter. The
    // value is a server-generated UUID path (no user input) with single quotes
    // escaped, so asserting SQL safety is sound and keeps sqlx 0.9's
    // injection guard intact for every user-derived query.
    sqlx::query(sqlx::AssertSqlSafe(format!(
        "VACUUM INTO '{}'",
        escaped_snapshot
    )))
    .execute(&state.db)
    .await?;

    let mut backup = Command::new(&bin);
    backup
        .arg("backup")
        .arg(&storage)
        .arg("--exclude")
        .arg(&trash)
        .arg("--exclude")
        .arg("**/.nexadrive-upload-*");
    backup.env("RESTIC_REPOSITORY", &repository);
    let output = backup.output().await.map_err(|_| {
        AppError::BadRequest("restic is not installed or cannot be executed".into())
    })?;
    let _ = fs::remove_file(&db_snapshot).await;
    if !output.status.success() {
        let message = String::from_utf8_lossy(&output.stderr).trim().to_string();
        create_notification(
            &state.db,
            user_id,
            "backup_failed",
            "Backup failed",
            &message,
            "error",
        )
        .await?;
        return Err(AppError::BadRequest(message));
    }
    let mut text = String::from_utf8_lossy(&output.stdout).to_string();
    if payload.prune.unwrap_or(false) {
        let mut prune = Command::new(&bin);
        prune
            .arg("forget")
            .arg("--keep-last")
            .arg("7")
            .arg("--keep-daily")
            .arg("14")
            .arg("--keep-weekly")
            .arg("8")
            .arg("--keep-monthly")
            .arg("12")
            .arg("--prune");
        prune.env("RESTIC_REPOSITORY", &repository);
        let prune_output = prune
            .output()
            .await
            .map_err(|_| AppError::BadRequest("restic prune could not be started".into()))?;
        if !prune_output.status.success() {
            let message = String::from_utf8_lossy(&prune_output.stderr)
                .trim()
                .to_string();
            create_notification(
                &state.db,
                user_id,
                "backup_prune_failed",
                "Backup retention cleanup failed",
                &message,
                "error",
            )
            .await?;
            return Err(AppError::BadRequest(message));
        }
        text.push('\n');
        text.push_str(&String::from_utf8_lossy(&prune_output.stdout));
    }
    audit(
        &state.db,
        user_id,
        "backup_run",
        Some(if payload.prune.unwrap_or(false) {
            "backup+prune"
        } else {
            "backup"
        }),
    )
    .await?;
    create_notification(
        &state.db,
        user_id,
        "backup_completed",
        "Backup completed",
        if payload.prune.unwrap_or(false) {
            "Backup and retention cleanup completed successfully."
        } else {
            "Backup completed successfully."
        },
        "info",
    )
    .await?;
    Ok(Json(BackupRunResponse {
        output: text.trim().to_string(),
    }))
}

pub(crate) async fn backup_check(
    State(state): State<AppState>,
    axum::extract::Extension(user_id): axum::extract::Extension<Uuid>,
) -> Result<Json<BackupCheckResponse>, AppError> {
    require_admin(&state.db, user_id).await?;
    let repository = state
        .config
        .restic_repository
        .clone()
        .ok_or_else(|| AppError::BadRequest("RESTIC_REPOSITORY is not configured".into()))?;
    if state.config.restic_password_file.is_none() {
        return Err(AppError::BadRequest(
            "RESTIC_PASSWORD_FILE is not configured".into(),
        ));
    }
    let bin = state.config.restic_bin.clone();
    let output = Command::new(&bin)
        .arg("check")
        .arg("--read-data-subset=5%")
        .env("RESTIC_REPOSITORY", &repository)
        .output()
        .await
        .map_err(|_| AppError::BadRequest("restic check could not be executed".into()))?;
    let stdout = String::from_utf8_lossy(&output.stdout).trim().to_string();
    let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
    let text = if stderr.is_empty() {
        stdout.clone()
    } else if stdout.is_empty() {
        stderr.clone()
    } else {
        format!("{}\n{}", stdout, stderr)
    };
    if !output.status.success() {
        create_notification(
            &state.db,
            user_id,
            "backup_check_failed",
            "Backup verification failed",
            &text,
            "error",
        )
        .await?;
        return Err(AppError::BadRequest(text));
    }
    audit(
        &state.db,
        user_id,
        "backup_check",
        Some("restic check --read-data-subset=5%"),
    )
    .await?;
    create_notification(
        &state.db,
        user_id,
        "backup_check_completed",
        "Backup verified",
        "Restic verified a 5% data subset successfully.",
        "info",
    )
    .await?;
    Ok(Json(BackupCheckResponse {
        output: text,
        verified: true,
    }))
}

pub(crate) async fn backup_snapshots(
    State(state): State<AppState>,
    axum::extract::Extension(user_id): axum::extract::Extension<Uuid>,
) -> Result<Json<Vec<BackupSnapshotResponse>>, AppError> {
    require_admin(&state.db, user_id).await?;
    let repository = state
        .config
        .restic_repository
        .clone()
        .ok_or_else(|| AppError::BadRequest("RESTIC_REPOSITORY is not configured".into()))?;
    if state.config.restic_password_file.is_none() {
        return Err(AppError::BadRequest(
            "RESTIC_PASSWORD_FILE is not configured".into(),
        ));
    }
    let bin = state.config.restic_bin.clone();
    let output = Command::new(&bin)
        .arg("snapshots")
        .arg("--json")
        .env("RESTIC_REPOSITORY", &repository)
        .output()
        .await
        .map_err(|_| {
            AppError::BadRequest("restic is not installed or cannot be executed".into())
        })?;
    if !output.status.success() {
        return Err(AppError::BadRequest(
            String::from_utf8_lossy(&output.stderr).trim().to_string(),
        ));
    }
    let raw: serde_json::Value =
        serde_json::from_slice(&output.stdout).map_err(|_| AppError::Internal)?;
    let mut result = Vec::new();
    if let Some(items) = raw.as_array() {
        for item in items.iter().take(100) {
            let id = item
                .get("id")
                .and_then(|v| v.as_str())
                .unwrap_or_default()
                .to_string();
            let time = item
                .get("time")
                .and_then(|v| v.as_str())
                .and_then(|v| v.parse::<DateTime<Utc>>().ok())
                .unwrap_or_else(Utc::now);
            let hostname = item
                .get("hostname")
                .and_then(|v| v.as_str())
                .map(str::to_string);
            let paths = item
                .get("paths")
                .and_then(|v| v.as_array())
                .map(|a| {
                    a.iter()
                        .filter_map(|v| v.as_str().map(str::to_string))
                        .collect()
                })
                .unwrap_or_default();
            result.push(BackupSnapshotResponse {
                id,
                time,
                hostname,
                paths,
            });
        }
    }
    Ok(Json(result))
}

pub(crate) async fn backup_restore(
    State(state): State<AppState>,
    axum::extract::Extension(user_id): axum::extract::Extension<Uuid>,
    Json(payload): Json<BackupRestoreRequest>,
) -> Result<Json<serde_json::Value>, AppError> {
    require_admin(&state.db, user_id).await?;
    if payload.snapshot_id.len() > 128
        || !payload
            .snapshot_id
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || matches!(c, '-' | '_'))
    {
        return Err(AppError::BadRequest("Invalid snapshot id".into()));
    }
    let repository = state
        .config
        .restic_repository
        .clone()
        .ok_or_else(|| AppError::BadRequest("RESTIC_REPOSITORY is not configured".into()))?;
    if state.config.restic_password_file.is_none() {
        return Err(AppError::BadRequest(
            "RESTIC_PASSWORD_FILE is not configured".into(),
        ));
    }
    let bin = state.config.restic_bin.clone();
    let root = state.storage_root.join(".restic-restores").join(format!(
        "{}-{}",
        Utc::now().format("%Y%m%dT%H%M%SZ"),
        payload.snapshot_id
    ));
    fs::create_dir_all(&root).await?;
    let output = Command::new(&bin)
        .arg("restore")
        .arg(&payload.snapshot_id)
        .arg("--target")
        .arg(&root)
        .env("RESTIC_REPOSITORY", &repository)
        .output()
        .await
        .map_err(|_| AppError::BadRequest("restic restore could not be executed".into()))?;
    if !output.status.success() {
        let _ = fs::remove_dir_all(&root).await;
        create_notification(
            &state.db,
            user_id,
            "backup_restore_failed",
            "Backup restore failed",
            String::from_utf8_lossy(&output.stderr).trim(),
            "error",
        )
        .await?;
        return Err(AppError::BadRequest(
            String::from_utf8_lossy(&output.stderr).trim().to_string(),
        ));
    }
    audit(
        &state.db,
        user_id,
        "backup_restore",
        Some(&payload.snapshot_id),
    )
    .await?;
    create_notification(
        &state.db,
        user_id,
        "backup_restore_ready",
        "Backup restore ready",
        &format!(
            "Snapshot {} was restored to {}. No live files were overwritten.",
            payload.snapshot_id,
            root.display()
        ),
        "info",
    )
    .await?;
    Ok(Json(
        serde_json::json!({"snapshot_id":payload.snapshot_id,"restore_path":root.to_string_lossy()}),
    ))
}
