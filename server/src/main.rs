mod auth;
mod config;
mod console;
mod error;
mod handlers;
mod logbuf;
mod metrics;
mod middleware;
mod models;
mod paths;
mod routes;
mod state;
mod storage_stats;

use std::{
    collections::HashMap,
    sync::{Arc, Mutex},
    time::Duration,
};

use chrono::Utc;
use sqlx::sqlite::{SqliteConnectOptions, SqlitePoolOptions};
use tokio::fs;
use tracing::{error, info};
use uuid::Uuid;

use crate::{
    auth::bootstrap_admin,
    config::Config,
    handlers::upload::{cleanup_stale_uploads, recover_upload_jobs, sweep_expired_uploads},
    logbuf::LogBuffer,
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
    let logs = LogBuffer::new();
    tracing_subscriber::fmt()
        .with_env_filter(config.rust_log.clone())
        .with_ansi(false)
        .with_writer(logbuf::LogMakeWriter::new(logs.clone()))
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

    cleanup_stale_uploads(&db, &config.storage_root, config.upload_session_ttl_hours).await?;
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
        metrics: Arc::new(metrics::Metrics::new()),
        logs,
        console_attempts: Arc::new(Mutex::new(HashMap::new())),
        storage_cache: Arc::new(Mutex::new(None)),
        upload_slots: Arc::new(tokio::sync::Semaphore::new(config.max_concurrent_uploads)),
        upload_locks: Arc::new(Mutex::new(HashMap::new())),
        quota_cache: Arc::new(Mutex::new(HashMap::new())),
    };

    // Upload sessions that were never finished must not keep their staging
    // files forever.
    {
        let db = state.db.clone();
        let storage_root = (*state.storage_root).clone();
        let ttl_hours = config.upload_session_ttl_hours;
        tokio::spawn(async move {
            loop {
                tokio::time::sleep(Duration::from_secs(15 * 60)).await;
                match sweep_expired_uploads(&db, &storage_root, ttl_hours).await {
                    Ok(expired) if expired > 0 => {
                        info!(expired, "expired stale upload sessions");
                    }
                    Ok(_) => {}
                    Err(e) => error!(error = %e, "failed to sweep expired upload sessions"),
                }
            }
        });
    }

    metrics::spawn_sampler(
        Arc::clone(&state.metrics),
        state.db.clone(),
        (*state.storage_root).clone(),
        config.database_path.clone(),
    );

    let app = routes::app(state.clone(), &config);

    // The console is loopback-only. Bind it first so a misconfiguration fails
    // fast at startup instead of silently exposing a control plane. The public
    // listener is never affected by console availability.
    let console_listener = if config.console_enabled() {
        if !config::is_loopback_bind(&config.console_bind_addr) {
            return Err(format!(
                "CONSOLE_BIND_ADDR '{}' is not a loopback address; refusing to start the console",
                config.console_bind_addr
            )
            .into());
        }
        let listener = tokio::net::TcpListener::bind(&config.console_bind_addr).await?;
        info!(
            addr = %config.console_bind_addr,
            dist = %config.console_dist_dir.display(),
            "NexaDrive console listening (loopback only)"
        );
        Some(listener)
    } else {
        info!("console disabled (CONSOLE_BIND_ADDR=off)");
        None
    };

    let bind_addr = config.bind_addr.clone();
    let listener = tokio::net::TcpListener::bind(&bind_addr).await?;
    info!(%bind_addr, "NexaDrive listening");

    if let Some(console_listener) = console_listener {
        let console_app = console::router(state.clone());
        tokio::spawn(async move {
            if let Err(err) = axum::serve(console_listener, console_app).await {
                error!(error = %err, "console server stopped");
            }
        });
    }

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
