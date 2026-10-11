use axum::{
    Router,
    extract::DefaultBodyLimit,
    http::{HeaderValue, header},
    middleware,
    routing::{get, post, put},
};
use tower_http::{cors::CorsLayer, limit::RequestBodyLimitLayer, trace::TraceLayer};

use crate::{
    auth::{auth_middleware, login, logout, me},
    config::Config,
    handlers::{
        admin::{
            create_user, delete_user, list_audit, list_users, revoke_user_sessions, update_user,
        },
        backup::{backup_check, backup_restore, backup_run, backup_snapshots, backup_status},
        download::{download_file, thumbnail},
        files::{
            batch_files, copy_file, create_folder, delete_file, list_files, list_photos, move_file,
            rename_file, search_files,
        },
        notifications::{list_notifications, mark_notifications_read},
        sharing::{
            create_share, delete_share, download_shared_file, list_shared, list_shared_items,
            list_shares, public_share_download, shared_action,
        },
        storage::{list_trash, permanently_delete_trash, restore_trash, storage},
        sync::{
            delete_sync_device, list_sync_devices, rename_sync_device, sync_delete, sync_delta,
            sync_manifest,
        },
        system::{health, server_status},
        upload::{upload_chunk, upload_file, upload_status},
    },
    middleware::security_headers,
    state::AppState,
};

pub(crate) fn app(state: AppState, config: &Config) -> Router {
    let public = Router::new()
        .route("/health", get(health))
        .route("/api/server/status", get(server_status))
        .route("/api/auth/login", post(login))
        .route("/api/share/{token}/download", get(public_share_download));

    let max_upload_bytes = config.max_upload_bytes;

    let protected = Router::new()
        .route("/api/auth/logout", post(logout))
        .route("/api/me", get(me))
        .route("/api/admin/users", get(list_users).post(create_user))
        .route(
            "/api/admin/users/{id}",
            put(update_user).delete(delete_user),
        )
        .route(
            "/api/admin/users/{id}/revoke-sessions",
            post(revoke_user_sessions),
        )
        .route("/api/admin/audit", get(list_audit))
        .route(
            "/api/shares",
            get(list_shares).post(create_share).delete(delete_share),
        )
        .route("/api/shared", get(list_shared))
        .route("/api/shared/items", get(list_shared_items))
        .route("/api/shared/download", get(download_shared_file))
        .route("/api/shared/action", post(shared_action))
        .route("/api/files", get(list_files).delete(delete_file))
        .route("/api/files/search", get(search_files))
        .route("/api/files/rename", post(rename_file))
        .route("/api/files/move", post(move_file))
        .route("/api/files/copy", post(copy_file))
        .route("/api/files/batch", post(batch_files))
        .route("/api/files/download", get(download_file))
        .route("/api/files/thumbnail", get(thumbnail))
        .route("/api/files/upload", post(upload_file))
        .route("/api/uploads/status", get(upload_status))
        .route("/api/uploads/chunk", post(upload_chunk))
        .route("/api/sync/manifest", get(sync_manifest))
        .route("/api/sync/delta", get(sync_delta))
        .route("/api/sync/delete", post(sync_delete))
        .route(
            "/api/sync/devices",
            get(list_sync_devices)
                .delete(delete_sync_device)
                .patch(rename_sync_device),
        )
        .route("/api/backup/status", get(backup_status))
        .route("/api/backup/run", post(backup_run))
        .route("/api/backup/snapshots", get(backup_snapshots))
        .route("/api/backup/restore", post(backup_restore))
        .route("/api/backup/check", post(backup_check))
        .route("/api/notifications", get(list_notifications))
        .route("/api/notifications/read", post(mark_notifications_read))
        .route("/api/photos", get(list_photos))
        .route("/api/folders", post(create_folder))
        .route("/api/storage", get(storage))
        .route(
            "/api/trash",
            get(list_trash).delete(permanently_delete_trash),
        )
        .route("/api/trash/restore", post(restore_trash))
        .layer(DefaultBodyLimit::max(max_upload_bytes))
        .layer(RequestBodyLimitLayer::new(max_upload_bytes))
        .layer(middleware::from_fn_with_state(
            state.clone(),
            auth_middleware,
        ));

    let allowed_origins = &config.cors_origins;
    let cors = if allowed_origins.trim() == "*" {
        CorsLayer::very_permissive()
    } else {
        let origins = allowed_origins
            .split(',')
            .map(str::trim)
            .filter(|raw| !raw.is_empty())
            .filter_map(|raw| raw.parse::<HeaderValue>().ok())
            .collect::<Vec<_>>();
        if origins.is_empty() {
            CorsLayer::new()
        } else {
            CorsLayer::new()
                .allow_origin(origins)
                .allow_headers([header::AUTHORIZATION, header::CONTENT_TYPE])
                .allow_methods([
                    axum::http::Method::GET,
                    axum::http::Method::POST,
                    axum::http::Method::PUT,
                    axum::http::Method::DELETE,
                ])
        }
    };

    public
        .merge(protected)
        .with_state(state)
        .layer(cors)
        .layer(middleware::from_fn(security_headers))
        .layer(TraceLayer::new_for_http())
}
