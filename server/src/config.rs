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
    pub(crate) max_concurrent_uploads: usize,
    pub(crate) upload_session_ttl_hours: i64,
    pub(crate) cors_origins: String,
    pub(crate) rust_log: String,
    pub(crate) restic_repository: Option<String>,
    pub(crate) restic_password_file: Option<String>,
    pub(crate) restic_bin: String,

    // ------------------------------------------------- local console (dashboard)
    /// Loopback-only bind address for the administration console. `off` (or an
    /// empty value) disables the console entirely.
    pub(crate) console_bind_addr: String,
    /// Directory holding the built dashboard (index.html + assets).
    pub(crate) console_dist_dir: PathBuf,
    /// Console session lifetime in hours.
    pub(crate) console_session_ttl_hours: i64,
    /// Whether the guarded "restart NexaDrive" action is enabled. Off by
    /// default; even when on, it only runs a fixed helper with no arguments.
    pub(crate) console_allow_restart: bool,
    /// Absolute path to the argument-less restart helper. Never user-supplied.
    pub(crate) console_restart_helper: String,
}

impl Config {
    pub(crate) fn from_env() -> Self {
        let console_bind_addr = std::env::var("CONSOLE_BIND_ADDR")
            .ok()
            .map(|v| v.trim().to_string())
            .filter(|v| !v.is_empty())
            .unwrap_or_else(|| "127.0.0.1:8090".into());
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
            // How many upload streams may be in flight at once. Each stream
            // holds a task, a file handle and a connection, so the server
            // caps them instead of trusting every client to be polite.
            max_concurrent_uploads: std::env::var("MAX_CONCURRENT_UPLOADS")
                .ok()
                .and_then(|v| v.parse().ok())
                .filter(|v| *v > 0)
                .unwrap_or(8),
            // How long an unfinished upload session (and its staging file) is
            // kept so a client can resume after a crash or a server restart.
            upload_session_ttl_hours: std::env::var("UPLOAD_SESSION_TTL_HOURS")
                .ok()
                .and_then(|v| v.parse().ok())
                .filter(|v| *v > 0)
                .unwrap_or(24),
            cors_origins: std::env::var("CORS_ORIGINS").unwrap_or_default(),
            rust_log: std::env::var("RUST_LOG")
                .unwrap_or_else(|_| "info,nexadrive_server=debug".into()),
            restic_repository: std::env::var("RESTIC_REPOSITORY").ok(),
            restic_password_file: std::env::var("RESTIC_PASSWORD_FILE").ok(),
            restic_bin: std::env::var("RESTIC_BIN").unwrap_or_else(|_| "restic".into()),

            console_bind_addr,
            console_dist_dir: PathBuf::from(
                std::env::var("CONSOLE_DIST_DIR").unwrap_or_else(|_| "../dashboard/dist".into()),
            ),
            console_session_ttl_hours: std::env::var("CONSOLE_SESSION_TTL_HOURS")
                .ok()
                .and_then(|v| v.parse().ok())
                .filter(|v| *v > 0 && *v <= 24 * 14)
                .unwrap_or(12),
            console_allow_restart: std::env::var("CONSOLE_ALLOW_RESTART")
                .map(|v| matches!(v.trim().to_ascii_lowercase().as_str(), "1" | "true" | "yes"))
                .unwrap_or(false),
            console_restart_helper: std::env::var("CONSOLE_RESTART_HELPER")
                .unwrap_or_else(|_| "/usr/local/libexec/nexadrive-restart".into()),
        }
    }

    /// Whether the local console should be started at all.
    pub(crate) fn console_enabled(&self) -> bool {
        !self.console_bind_addr.eq_ignore_ascii_case("off")
    }
}

/// True when `addr` is a `host:port` whose host is a loopback address.
///
/// Used as a hard startup gate: the console refuses to run on any other
/// interface so a misconfiguration can never publish the control plane.
pub(crate) fn is_loopback_bind(addr: &str) -> bool {
    let host = if let Some(rest) = addr.strip_prefix('[') {
        // IPv6 literal: [::1]:8090
        match rest.split_once(']') {
            Some((h, _)) => h,
            None => return false,
        }
    } else {
        match addr.rsplit_once(':') {
            Some((h, _)) => h,
            None => return false,
        }
    };
    matches!(host, "127.0.0.1" | "::1" | "localhost")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn loopback_binds_are_accepted() {
        assert!(is_loopback_bind("127.0.0.1:8090"));
        assert!(is_loopback_bind("127.0.0.1:0"));
        assert!(is_loopback_bind("[::1]:8090"));
        assert!(is_loopback_bind("localhost:8090"));
    }

    #[test]
    fn non_loopback_binds_are_rejected() {
        assert!(!is_loopback_bind("0.0.0.0:8090"));
        assert!(!is_loopback_bind("192.168.1.10:8090"));
        assert!(!is_loopback_bind("100.87.162.46:8090"));
        assert!(!is_loopback_bind("[::]:8090"));
        assert!(!is_loopback_bind("example.com:8090"));
        assert!(!is_loopback_bind("8090"));
    }
}
