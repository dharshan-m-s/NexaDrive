use axum::{
    extract::{Extension, State},
    http::{HeaderMap, HeaderValue, Method, StatusCode, header},
    middleware,
    response::{IntoResponse, Response},
};
use serde::Serialize;
use sqlx::{Row, SqlitePool};
use std::time::Instant;
use uuid::Uuid;

use crate::{
    auth::{new_token, token_hash, verify_password},
    error::AppError,
    handlers::admin::audit_event,
    models::LoginRequest,
    state::{AppState, LoginAttempt},
};

/// HttpOnly session cookie. Not `Secure`: the console is served over plain
/// HTTP on the loopback interface, and marking it Secure would stop the cookie
/// from being sent and break the app. Loopback-only binding, a strict Host
/// allowlist, SameSite=Strict and CSRF tokens are the actual controls.
pub(crate) const CONSOLE_COOKIE: &str = "nexa_console";
/// Double-submit CSRF cookie (readable by same-origin JS).
pub(crate) const CSRF_COOKIE: &str = "nexa_console_csrf";
/// Header the SPA must echo the CSRF cookie in for state-changing requests.
pub(crate) const CSRF_HEADER: &str = "x-csrf-token";

#[derive(Serialize)]
pub(crate) struct ConsoleUser {
    pub(crate) id: Uuid,
    pub(crate) username: String,
    pub(crate) display_name: String,
    pub(crate) role: String,
}

#[derive(Serialize)]
pub(crate) struct ConsoleLoginResponse {
    pub(crate) user: ConsoleUser,
    pub(crate) csrf_token: String,
}

pub(crate) fn parse_cookie(headers: &HeaderMap, name: &str) -> Option<String> {
    let raw = headers.get(header::COOKIE)?.to_str().ok()?;
    for pair in raw.split(';') {
        if let Some((k, v)) = pair.split_once('=')
            && k.trim() == name
        {
            return Some(v.trim().to_string());
        }
    }
    None
}

fn cookie_header(name: &str, value: &str, ttl_secs: i64, http_only: bool) -> String {
    let mut s = format!("{name}={value}; Path=/; SameSite=Strict; Max-Age={ttl_secs}");
    if http_only {
        s.push_str("; HttpOnly");
    }
    s
}

fn clear_cookie_header(name: &str) -> String {
    format!("{name}=; Path=/; SameSite=Strict; Max-Age=0; HttpOnly")
}

/// Sets a cookie on a response. Values produced here are always
/// ASCII (`new_token` output or a fixed literal), so a parse failure means the
/// value was corrupted and must not be silently dropped.
fn append_set_cookie(response: &mut Response, value: &str) -> Result<(), AppError> {
    let value = HeaderValue::from_str(value).map_err(|_| AppError::Internal)?;
    response.headers_mut().append(header::SET_COOKIE, value);
    Ok(())
}

/// Throttles failed console sign-ins per username (10 / 15 min), mirroring the
/// public login policy but on a separate counter map.
fn check_attempts(state: &AppState, key: &str) -> Result<(), AppError> {
    let guard = state
        .console_attempts
        .lock()
        .map_err(|_| AppError::Internal)?;
    if let Some(entry) = guard.get(key) {
        let fresh = Instant::now().duration_since(entry.window_started)
            <= std::time::Duration::from_secs(15 * 60);
        if fresh && entry.failures >= 10 {
            return Err(AppError::TooManyRequests);
        }
    }
    Ok(())
}

fn register_attempt(state: &AppState, key: &str) -> Result<(), AppError> {
    let mut guard = state
        .console_attempts
        .lock()
        .map_err(|_| AppError::Internal)?;
    let now = Instant::now();
    let entry = guard.entry(key.to_string()).or_insert(LoginAttempt {
        window_started: now,
        failures: 0,
    });
    if now.duration_since(entry.window_started) > std::time::Duration::from_secs(15 * 60) {
        *entry = LoginAttempt {
            window_started: now,
            failures: 0,
        };
    }
    entry.failures = entry.failures.saturating_add(1);
    Ok(())
}

fn clear_attempts(state: &AppState, key: &str) -> Result<(), AppError> {
    let mut guard = state
        .console_attempts
        .lock()
        .map_err(|_| AppError::Internal)?;
    guard.remove(key);
    Ok(())
}

/// Records a failed console sign-in. Unknown usernames are logged with a NULL
/// actor so brute-force attempts on any name remain visible in the audit log.
async fn audit_login_failure(db: &SqlitePool, user_id: Option<Uuid>, subject: &str) {
    let subject = subject.chars().take(64).collect::<String>();
    let _ = sqlx::query(
        "INSERT INTO audit_logs (id, user_id, action, target, outcome, detail) \
         VALUES ($1, $2, 'login', $3, 'failed', 'invalid credentials')",
    )
    .bind(Uuid::new_v4())
    .bind(user_id)
    .bind(subject)
    .execute(db)
    .await;
}

pub(crate) async fn session_info(
    State(state): State<AppState>,
    Extension(user_id): Extension<Uuid>,
) -> Result<axum::Json<ConsoleUser>, AppError> {
    let row = sqlx::query(
        "SELECT id, username, display_name, role FROM users WHERE id = $1 AND disabled = FALSE",
    )
    .bind(user_id)
    .fetch_optional(&state.db)
    .await?
    .ok_or(AppError::Unauthorized)?;
    Ok(axum::Json(ConsoleUser {
        id: row.get("id"),
        username: row.get("username"),
        display_name: row.get("display_name"),
        role: row.get("role"),
    }))
}

/// Issues a console session cookie for an administrator.
///
/// Only members of the `admin` role may sign in to the console; ordinary
/// users get `403` so the attempt is never distinguishable from a wrong
/// password by timing on the unknown-user branch.
pub(crate) async fn login(
    State(state): State<AppState>,
    axum::Json(payload): axum::Json<LoginRequest>,
) -> Result<Response, AppError> {
    let subject = payload.username.trim();
    let key = format!("user:{}", subject.to_lowercase());
    check_attempts(&state, &key)?;

    let row = sqlx::query(
        "SELECT id, username, display_name, role, password_hash \
         FROM users WHERE username = $1 AND disabled = FALSE",
    )
    .bind(subject)
    .fetch_optional(&state.db)
    .await?;

    let row = match row {
        Some(row) => row,
        None => {
            let _ = register_attempt(&state, &key);
            audit_login_failure(&state.db, None, subject).await;
            return Err(AppError::Unauthorized);
        }
    };

    let password_hash: String = row.get("password_hash");
    let user_id: Uuid = row.get("id");
    let role: String = row.get("role");

    if !verify_password(&payload.password, &password_hash) {
        let _ = register_attempt(&state, &key);
        audit_login_failure(&state.db, Some(user_id), subject).await;
        return Err(AppError::Unauthorized);
    }

    if role != "admin" {
        audit_event(
            &state.db,
            user_id,
            "login",
            Some(subject),
            "denied",
            Some("console requires an administrator account"),
        )
        .await?;
        return Err(AppError::Forbidden);
    }

    clear_attempts(&state, &key)?;

    let ttl_hours = state.config.console_session_ttl_hours;
    let ttl_secs = ttl_hours * 3600;
    let token = new_token();
    let csrf = new_token();
    sqlx::query(
        "INSERT INTO console_sessions \
         (id, user_id, token_hash, csrf_hash, created_at, last_seen_at, expires_at) \
         VALUES ($1, $2, $3, $4, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, datetime('now', $5))",
    )
    .bind(Uuid::new_v4())
    .bind(user_id)
    .bind(token_hash(&token))
    .bind(token_hash(&csrf))
    .bind(format!("+{ttl_hours} hours"))
    .execute(&state.db)
    .await?;

    audit_event(&state.db, user_id, "login", Some(subject), "success", None).await?;

    let user = ConsoleUser {
        id: user_id,
        username: row.get("username"),
        display_name: row.get("display_name"),
        role,
    };
    let session_cookie = cookie_header(CONSOLE_COOKIE, &token, ttl_secs, true);
    let csrf_cookie = cookie_header(CSRF_COOKIE, &csrf, ttl_secs, false);
    let body = serde_json::to_string(&ConsoleLoginResponse {
        user,
        csrf_token: csrf,
    })
    .map_err(|_| AppError::Internal)?;

    let mut response = (
        StatusCode::OK,
        [(header::CONTENT_TYPE, "application/json")],
        body,
    )
        .into_response();
    append_set_cookie(&mut response, &session_cookie)?;
    append_set_cookie(&mut response, &csrf_cookie)?;
    Ok(response)
}

/// Signs the administrator out of this browser. The route sits behind
/// `require_console_admin`, so a valid session and a matching CSRF header are
/// already proven by the time this runs; the extension carries the actor.
pub(crate) async fn logout(
    State(state): State<AppState>,
    headers: HeaderMap,
    Extension(user_id): Extension<Uuid>,
) -> Result<Response, AppError> {
    if let Some(token) = parse_cookie(&headers, CONSOLE_COOKIE) {
        sqlx::query("DELETE FROM console_sessions WHERE token_hash = $1")
            .bind(token_hash(&token))
            .execute(&state.db)
            .await?;
    }
    let _ = audit_event(&state.db, user_id, "logout", None, "success", None).await;

    let mut response = StatusCode::NO_CONTENT.into_response();
    append_set_cookie(&mut response, &clear_cookie_header(CONSOLE_COOKIE))?;
    append_set_cookie(&mut response, &clear_cookie_header(CSRF_COOKIE))?;
    Ok(response)
}

/// Middleware that resolves the console session cookie, enforces admin
/// privileges, and, for state-changing requests, checks the CSRF double-submit.
pub(crate) async fn require_console_admin(
    State(state): State<AppState>,
    headers: HeaderMap,
    mut request: axum::extract::Request,
    next: middleware::Next,
) -> Result<Response, AppError> {
    let token = parse_cookie(&headers, CONSOLE_COOKIE).ok_or(AppError::Unauthorized)?;
    let hash = token_hash(&token);

    let row = sqlx::query(
        "SELECT cs.csrf_hash, u.id AS user_id, u.role \
         FROM console_sessions cs \
         JOIN users u ON u.id = cs.user_id \
         WHERE cs.token_hash = $1 AND cs.expires_at > CURRENT_TIMESTAMP \
           AND u.disabled = FALSE",
    )
    .bind(&hash)
    .fetch_optional(&state.db)
    .await?
    .ok_or(AppError::Unauthorized)?;

    let role: String = row.get("role");
    if role != "admin" {
        return Err(AppError::Forbidden);
    }

    let method = request.method().clone();
    if !matches!(method, Method::GET | Method::HEAD | Method::OPTIONS) {
        let csrf = headers
            .get(CSRF_HEADER)
            .and_then(|v| v.to_str().ok())
            .ok_or(AppError::Forbidden)?;
        let stored: String = row.get("csrf_hash");
        if token_hash(csrf) != stored {
            return Err(AppError::Forbidden);
        }
    }

    request
        .extensions_mut()
        .insert(row.get::<Uuid, _>("user_id"));

    // Refresh the "last seen" stamp at most once a minute so a busy console
    // does not write to the database on every poll.
    let _ = sqlx::query(
        "UPDATE console_sessions SET last_seen_at = CURRENT_TIMESTAMP \
         WHERE token_hash = $1 \
           AND (last_seen_at IS NULL OR last_seen_at < datetime('now','-60 seconds'))",
    )
    .bind(&hash)
    .execute(&state.db)
    .await;

    Ok(next.run(request).await)
}

/// Re-authentication for destructive actions: verifies the admin's password
/// without creating a new session. Returns a generic error so it cannot be
/// used to distinguish account state.
pub(crate) async fn reauthenticate(
    state: &AppState,
    user_id: Uuid,
    password: &str,
) -> Result<(), AppError> {
    let row = sqlx::query("SELECT password_hash FROM users WHERE id = $1 AND disabled = FALSE")
        .bind(user_id)
        .fetch_optional(&state.db)
        .await?
        .ok_or(AppError::Unauthorized)?;
    let hash: String = row.get("password_hash");
    if verify_password(password, &hash) {
        Ok(())
    } else {
        Err(AppError::Forbidden)
    }
}

/// Verifies the supplied password against the acting admin. Used by
/// destructive endpoints before they act.
pub(crate) async fn confirm_password(
    state: &AppState,
    user_id: Uuid,
    password: &str,
) -> Result<(), AppError> {
    reauthenticate(state, user_id, password).await
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn password_verification_accepts_only_the_exact_password() {
        let hash = crate::auth::hash_password("correct horse battery staple").unwrap();
        assert!(verify_password("correct horse battery staple", &hash));
        assert!(!verify_password("wrong password", &hash));
        assert!(!verify_password("", &hash));
    }

    #[test]
    fn hashing_round_trips() {
        let hash = crate::auth::hash_password("correct horse battery staple").unwrap();
        assert!(verify_password("correct horse battery staple", &hash));
        assert!(!verify_password("wrong", &hash));
    }

    #[test]
    fn parses_cookies() {
        let mut headers = HeaderMap::new();
        headers.insert(
            header::COOKIE,
            "a=1; nexa_console=secret; b=2".parse().unwrap(),
        );
        assert_eq!(
            parse_cookie(&headers, CONSOLE_COOKIE),
            Some("secret".into())
        );
        assert_eq!(parse_cookie(&headers, "missing"), None);
        assert_eq!(parse_cookie(&headers, "csrf"), None);
    }

    #[test]
    fn session_cookie_is_httponly_and_csrf_is_readable() {
        let session = cookie_header(CONSOLE_COOKIE, "token", 3600, true);
        assert!(session.contains("HttpOnly"));
        assert!(session.contains("SameSite=Strict"));
        assert!(session.contains("Max-Age=3600"));

        let csrf = cookie_header(CSRF_COOKIE, "token", 3600, false);
        assert!(!csrf.contains("HttpOnly"), "SPA must read the csrf cookie");
    }

    #[test]
    fn clearing_cookie_expires_immediately() {
        assert!(clear_cookie_header(CONSOLE_COOKIE).contains("Max-Age=0"));
    }

    #[test]
    fn csrf_and_session_cookie_names_do_not_collide() {
        assert_ne!(CONSOLE_COOKIE, CSRF_COOKIE);
        assert_ne!(CSRF_COOKIE, CSRF_HEADER);
    }
}
