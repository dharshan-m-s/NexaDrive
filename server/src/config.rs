use std::path::PathBuf;

/// All environment-driven configuration, read once at startup.
///
/// Preserves the exact defaults, parsing and fallbacks the server previously
/// applied ad hoc via `std::env::var` so behavior is unchanged. `ADMIN_PASSWORD`
/// stays optional: it is only required when the database has no users yet.
pub(crate) struct Config {
    pub(crate) database_path: String,
    pub(crate) storage_root: PathBuf,
    pub(crate) bind_addr: String,
    pub(crate) public_url: Option<String>,
    pub(crate) admin_username: String,
    pub(crate) admin_display_name: String,
    pub(crate) admin_password: Option<String>,
    pub(crate) max_upload_bytes: usize,
    pub(crate) cors_origins: String,
    pub(crate) rust_log: String,
    pub(crate) restic_repository: Option<String>,
    pub(crate) restic_password_file: Option<String>,
    pub(crate) restic_bin: String,
}

impl Config {
    pub(crate) fn from_env() -> Self {
        Self {
            database_path: std::env::var("DATABASE_PATH")
                .unwrap_or_else(|_| "./data/nexadrive.db".into()),
            storage_root: PathBuf::from(
                std::env::var("STORAGE_ROOT").unwrap_or_else(|_| "./storage".into()),
            ),
            bind_addr: std::env::var("BIND_ADDR").unwrap_or_else(|_| "127.0.0.1:8080".into()),
            public_url: std::env::var("PUBLIC_URL")
                .ok()
                .map(|v| v.trim().trim_end_matches('/').to_string())
                .filter(|v| !v.is_empty()),
            admin_username: std::env::var("ADMIN_USERNAME").unwrap_or_else(|_| "admin".into()),
            admin_display_name: std::env::var("ADMIN_DISPLAY_NAME")
                .unwrap_or_else(|_| "Administrator".into()),
            admin_password: std::env::var("ADMIN_PASSWORD").ok(),
            max_upload_bytes: std::env::var("MAX_UPLOAD_BYTES")
                .ok()
                .and_then(|v| v.parse().ok())
                .unwrap_or(10usize * 1024 * 1024 * 1024),
            cors_origins: std::env::var("CORS_ORIGINS").unwrap_or_default(),
            rust_log: std::env::var("RUST_LOG")
                .unwrap_or_else(|_| "info,nexadrive_server=debug".into()),
            restic_repository: std::env::var("RESTIC_REPOSITORY").ok(),
            restic_password_file: std::env::var("RESTIC_PASSWORD_FILE").ok(),
            restic_bin: std::env::var("RESTIC_BIN").unwrap_or_else(|_| "restic".into()),
        }
    }
}
