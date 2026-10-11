mod auth;
mod config;
mod error;
mod handlers;
mod middleware;
mod models;
mod paths;
mod routes;
mod state;

use std::{
    collections::HashMap,
    sync::{Arc, Mutex},
    time::Duration,
};

use chrono::Utc;
use sqlx::sqlite::{SqliteConnectOptions, SqlitePoolOptions};
use tokio::fs;
use tracing::info;
use uuid::Uuid;

use crate::{
    auth::bootstrap_admin,
    config::Config,
    handlers::upload::{cleanup_stale_uploads, recover_upload_jobs},
    state::AppState,
};

/// API surface version. Bump when incompatible client/server changes land so
/// old clients can show a clear "update your client/server" message instead of
/// failing with obscure errors.
pub(crate) const API_VERSION: &str = "1.0.0";

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    dotenvy::dotenv().ok();
    let config = Arc::new(Config::from_env());
    tracing_subscriber::fmt()
        .with_env_filter(config.rust_log.clone())
        .init();

    if let Some(parent) = std::path::Path::new(&config.database_path).parent() {
        fs::create_dir_all(parent).await?;
    }
    fs::create_dir_all(&config.storage_root).await?;
    fs::create_dir_all(config.storage_root.join(".trash")).await?;

    let db = SqlitePoolOptions::new()
        .max_connections(5)
        .connect_with(
            SqliteConnectOptions::new()
                .filename(&config.database_path)
                .create_if_missing(true)
                .foreign_keys(true)
                .journal_mode(sqlx::sqlite::SqliteJournalMode::Wal)
                .synchronous(sqlx::sqlite::SqliteSynchronous::Normal)
                .busy_timeout(Duration::from_secs(10)),
        )
        .await?;
    sqlx::migrate!("./migrations").run(&db).await?;
    bootstrap_admin(&db, &config).await?;

    cleanup_stale_uploads(&config.storage_root).await?;
    recover_upload_jobs(&db, &config.storage_root).await?;
    if let Some(url) = &config.public_url {
        info!(%url, "NexaDrive public URL configured");
    } else {
        info!("PUBLIC_URL not set; clients must supply the server address");
    }
    let state = AppState {
        db,
        storage_root: Arc::new(config.storage_root.clone()),
        instance_id: Uuid::new_v4(),
        started_at: Utc::now(),
        login_attempts: Arc::new(Mutex::new(HashMap::new())),
        share_download_attempts: Arc::new(Mutex::new(HashMap::new())),
        public_url: config.public_url.clone(),
        thumb_cache: Arc::new(Mutex::new(HashMap::new())),
        config: Arc::clone(&config),
    };

    let app = routes::app(state, &config);

    let bind_addr = config.bind_addr.clone();
    let listener = tokio::net::TcpListener::bind(&bind_addr).await?;
    info!(%bind_addr, "NexaDrive listening");
    axum::serve(listener, app).await?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::models::ServerStatus;

    #[test]
    fn server_status_carries_version_contract() {
        let status = ServerStatus {
            instance_id: Uuid::new_v4(),
            started_at: Utc::now(),
            status: "ok",
            public_url: None,
            version: env!("CARGO_PKG_VERSION"),
            api_version: API_VERSION,
        };
        assert!(!status.version.is_empty());
        assert_eq!(status.version, env!("CARGO_PKG_VERSION"));
        assert_eq!(status.api_version, API_VERSION);
    }

    #[test]
    fn api_version_is_stable_semver() {
        // The API contract token must look like MAJOR.MINOR.PATCH so the client
        // can compare it against the manifest's serverApiVersion.
        let parts: Vec<&str> = API_VERSION.split('.').collect();
        assert_eq!(parts.len(), 3);
        assert!(parts.iter().all(|p| p.parse::<u32>().is_ok()));
    }
}
