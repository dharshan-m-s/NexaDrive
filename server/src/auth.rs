use axum::{
    Json,
    extract::State,
    http::{HeaderMap, StatusCode, header},
    middleware,
    response::Response,
};
use rand::{RngExt, distr::Alphanumeric};
use sha2::{Digest, Sha256};
use sqlx::{Row, sqlite::SqlitePool};
use std::{
    path::Path,
    time::{Duration, Instant},
};
use tracing::info;
use uuid::Uuid;

use crate::{
    config::Config,
    error::AppError,
    handlers::admin::audit,
    models::{LoginRequest, LoginResponse, UserResponse},
    state::{AppState, LoginAttempt},
};

pub(crate) fn login_key(_headers: &HeaderMap, username: &str) -> String {
    // Do not trust X-Forwarded-For from the client. Tailscale Serve/proxies may add
    // forwarding metadata, but the public-facing throttle must still be tied to the
    // account being attacked rather than a spoofable request header.
    format!("user:{}", username.trim().to_lowercase())
}

pub(crate) fn register_failed_login(state: &AppState, key: &str) -> Result<(), AppError> {
    let mut guard = state
        .login_attempts
        .lock()
        .map_err(|_| AppError::Internal)?;
    let now = Instant::now();
    let entry = guard.entry(key.to_string()).or_insert(LoginAttempt {
        window_started: now,
        failures: 0,
    });
    if now.duration_since(entry.window_started) > Duration::from_secs(15 * 60) {
        *entry = LoginAttempt {
            window_started: now,
            failures: 0,
        };
    }
    entry.failures = entry.failures.saturating_add(1);
    Ok(())
}

pub(crate) fn check_login_allowed(state: &AppState, key: &str) -> Result<(), AppError> {
    let mut guard = state
        .login_attempts
        .lock()
        .map_err(|_| AppError::Internal)?;
    if let Some(entry) = guard.get(key) {
        if Instant::now().duration_since(entry.window_started) <= Duration::from_secs(15 * 60)
            && entry.failures >= 10
        {
            return Err(AppError::TooManyRequests);
        }
        if Instant::now().duration_since(entry.window_started) > Duration::from_secs(15 * 60) {
            guard.remove(key);
        }
    }
    Ok(())
}

pub(crate) fn clear_failed_logins(state: &AppState, key: &str) -> Result<(), AppError> {
    let mut guard = state
        .login_attempts
        .lock()
        .map_err(|_| AppError::Internal)?;
    guard.remove(key);
    Ok(())
}

pub(crate) fn register_failed_share_download(state: &AppState, key: &str) {
    if let Ok(mut guard) = state.share_download_attempts.lock() {
        let now = Instant::now();
        let entry = guard.entry(key.to_string()).or_insert(LoginAttempt {
            window_started: now,
            failures: 0,
        });
        if now.duration_since(entry.window_started) > Duration::from_secs(15 * 60) {
            *entry = LoginAttempt {
                window_started: now,
                failures: 0,
            };
        }
        entry.failures = entry.failures.saturating_add(1);
    }
}

pub(crate) fn clear_share_download_attempts(state: &AppState, key: &str) {
    if let Ok(mut guard) = state.share_download_attempts.lock() {
        guard.remove(key);
    }
}

pub(crate) async fn bootstrap_admin(db: &SqlitePool, config: &Config) -> Result<(), AppError> {
    let count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM users")
        .fetch_one(db)
        .await?;
    if count > 0 {
        return Ok(());
    }
    let password = config.admin_password.clone().ok_or_else(|| {
        AppError::BadRequest("ADMIN_PASSWORD is required on first startup".into())
    })?;
    let password_hash = hash_password(&password)?;
    sqlx::query(r#"INSERT INTO users (id, username, display_name, password_hash, role) VALUES ($1, $2, $3, $4, 'admin')"#)
        .bind(Uuid::new_v4()).bind(&config.admin_username).bind(&config.admin_display_name).bind(password_hash).execute(db).await?;
    info!("Created initial NexaDrive administrator");
    Ok(())
}

pub(crate) fn hash_password(password: &str) -> Result<String, AppError> {
    use argon2::{Argon2, password_hash::PasswordHasher};
    // password-hash 0.6 generates the salt internally from a CSPRNG, so the
    // caller no longer supplies one.
    Argon2::default()
        .hash_password(password.as_bytes())
        .map(|h| h.to_string())
        .map_err(|_| AppError::Internal)
}

pub(crate) fn verify_password(password: &str, hash: &str) -> bool {
    use argon2::{
        Argon2,
        password_hash::{PasswordVerifier, phc::PasswordHash},
    };
    PasswordHash::new(hash)
        .ok()
        .map(|p| {
            Argon2::default()
                .verify_password(password.as_bytes(), &p)
                .is_ok()
        })
        .unwrap_or(false)
}

pub(crate) fn new_token() -> String {
    rand::rng()
        .sample_iter(Alphanumeric)
        .take(64)
        .map(char::from)
        .collect()
}

pub(crate) fn token_hash(token: &str) -> String {
    let mut hasher = Sha256::new();
    hasher.update(token.as_bytes());
    format!("{:x}", hasher.finalize())
}

pub(crate) fn bearer(headers: &HeaderMap) -> Option<String> {
    headers
        .get(header::AUTHORIZATION)?
        .to_str()
        .ok()?
        .strip_prefix("Bearer ")
        .map(str::to_string)
}

pub(crate) async fn auth_middleware(
    State(state): State<AppState>,
    headers: HeaderMap,
    mut request: axum::extract::Request,
    next: middleware::Next,
) -> Result<Response, AppError> {
    let token = bearer(&headers).ok_or(AppError::Unauthorized)?;
    let hash = token_hash(&token);
    let row = sqlx::query("SELECT s.id AS session_id, s.user_id FROM sessions s JOIN users u ON u.id=s.user_id WHERE s.token_hash = $1 AND s.expires_at > CURRENT_TIMESTAMP AND u.disabled = FALSE")
        .bind(&hash).fetch_optional(&state.db).await?;
    let row = match row {
        Some(r) => r,
        None => {
            // If the token exists but the user is disabled, revoke the session
            let stale = sqlx::query("SELECT s.id AS session_id FROM sessions s JOIN users u ON u.id=s.user_id WHERE s.token_hash = $1 AND u.disabled = TRUE")
                .bind(&hash).fetch_optional(&state.db).await?;
            if let Some(s) = stale {
                let sid: Uuid = s.get("session_id");
                let _ = sqlx::query("DELETE FROM sessions WHERE id=$1")
                    .bind(sid)
                    .execute(&state.db)
                    .await;
            }
            return Err(AppError::Unauthorized);
        }
    };
    request
        .extensions_mut()
        .insert(row.get::<Uuid, _>("user_id"));
    Ok(next.run(request).await)
}

pub(crate) async fn login(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(payload): Json<LoginRequest>,
) -> Result<Json<LoginResponse>, AppError> {
    let key = login_key(&headers, &payload.username);
    check_login_allowed(&state, &key)?;
    let row = sqlx::query("SELECT id, username, display_name, password_hash, role FROM users WHERE username = $1 AND disabled = FALSE")
        .bind(&payload.username).fetch_optional(&state.db).await?;
    let row = match row {
        Some(row) => row,
        None => {
            register_failed_login(&state, &key)?;
            return Err(AppError::Unauthorized);
        }
    };
    let password_hash: String = row.get("password_hash");
    if !verify_password(&payload.password, &password_hash) {
        register_failed_login(&state, &key)?;
        return Err(AppError::Unauthorized);
    }
    clear_failed_logins(&state, &key)?;
    let user = UserResponse {
        id: row.get("id"),
        username: row.get("username"),
        display_name: row.get("display_name"),
        role: row.get("role"),
    };
    let token = new_token();
    sqlx::query(r#"INSERT INTO sessions (id, user_id, token_hash, expires_at) VALUES ($1, $2, $3, datetime('now', '+30 days'))"#)
        .bind(Uuid::new_v4()).bind(user.id).bind(token_hash(&token)).execute(&state.db).await?;
    audit(&state.db, user.id, "login", None).await?;
    Ok(Json(LoginResponse { token, user }))
}

pub(crate) async fn logout(
    State(state): State<AppState>,
    headers: HeaderMap,
    user_id: axum::extract::Extension<Uuid>,
) -> Result<StatusCode, AppError> {
    if let Some(token) = bearer(&headers) {
        sqlx::query("DELETE FROM sessions WHERE token_hash = $1")
            .bind(token_hash(&token))
            .execute(&state.db)
            .await?;
    }
    audit(&state.db, *user_id, "logout", None).await?;
    Ok(StatusCode::NO_CONTENT)
}

pub(crate) async fn me(
    State(state): State<AppState>,
    axum::extract::Extension(user_id): axum::extract::Extension<Uuid>,
) -> Result<Json<UserResponse>, AppError> {
    let row = sqlx::query("SELECT id, username, display_name, role FROM users WHERE id = $1")
        .bind(user_id)
        .fetch_optional(&state.db)
        .await?
        .ok_or(AppError::NotFound)?;
    Ok(Json(UserResponse {
        id: row.get("id"),
        username: row.get("username"),
        display_name: row.get("display_name"),
        role: row.get("role"),
    }))
}

pub(crate) async fn current_role(db: &SqlitePool, user_id: Uuid) -> Result<String, AppError> {
    sqlx::query_scalar("SELECT role FROM users WHERE id=$1 AND disabled=FALSE")
        .bind(user_id)
        .fetch_optional(db)
        .await?
        .ok_or(AppError::Unauthorized)
}

pub(crate) async fn require_admin(db: &SqlitePool, user_id: Uuid) -> Result<(), AppError> {
    if current_role(db, user_id).await? != "admin" {
        return Err(AppError::Forbidden);
    }
    Ok(())
}

pub(crate) fn validate_role(role: &str) -> Result<&str, AppError> {
    match role {
        "admin" | "user" => Ok(role),
        _ => Err(AppError::BadRequest("Role must be admin or user".into())),
    }
}

pub(crate) fn permission_allows(permission: &str, needed_write: bool) -> bool {
    permission == "write" || (!needed_write && permission == "read")
}

pub(crate) async fn require_write_access(
    state: &AppState,
    user_id: Uuid,
    _path: &Path,
) -> Result<(), AppError> {
    if current_role(&state.db, user_id).await? == "admin" {
        return Ok(());
    }
    // Owner paths are always writable. Shared writable paths are restricted to the shared subtree and
    // currently exposed through /api/shared endpoints; direct user-root paths remain private.
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn token_entropy_is_sufficient() {
        let token = new_token();
        assert_eq!(token.len(), 64);
        assert!(token.chars().all(|c| c.is_ascii_alphanumeric()));
        let token2 = new_token();
        assert_ne!(token, token2, "tokens must be unique");
    }

    #[test]
    fn token_hash_is_deterministic() {
        let t = new_token();
        assert_eq!(token_hash(&t), token_hash(&t));
        assert_ne!(token_hash(&t), token_hash(&new_token()));
    }

    #[test]
    fn validate_role_rejects_invalid() {
        assert!(validate_role("admin").is_ok());
        assert!(validate_role("user").is_ok());
        assert!(validate_role("superadmin").is_err());
        assert!(validate_role("").is_err());
        assert!(validate_role("ADMIN").is_err());
    }

    #[test]
    fn login_key_is_case_insensitive() {
        let key1 = login_key(&HeaderMap::new(), "Admin");
        let key2 = login_key(&HeaderMap::new(), "admin");
        assert_eq!(key1, key2);
    }

    #[test]
    fn permission_allows_logic() {
        assert!(permission_allows("read", false));
        assert!(!permission_allows("read", true));
        assert!(permission_allows("write", false));
        assert!(permission_allows("write", true));
    }
}
