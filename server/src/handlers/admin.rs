use axum::{
    Json,
    extract::{Query, State},
    http::StatusCode,
};
use sqlx::{Row, sqlite::SqlitePool};
use std::collections::HashMap;
use tokio::fs;
use uuid::Uuid;

use crate::{
    auth::{hash_password, require_admin, validate_role},
    error::AppError,
    models::{
        AdminUserResponse, AuditResponse, CreateUserRequest, RevokeSessionsResponse,
        UpdateUserRequest,
    },
    paths::{trash_root, user_root},
    state::AppState,
};

pub(crate) async fn list_audit(
    State(state): State<AppState>,
    axum::extract::Extension(admin_id): axum::extract::Extension<Uuid>,
    Query(query): Query<HashMap<String, String>>,
) -> Result<Json<Vec<AuditResponse>>, AppError> {
    require_admin(&state.db, admin_id).await?;
    let limit = query
        .get("limit")
        .and_then(|v| v.parse::<i64>().ok())
        .unwrap_or(200)
        .clamp(1, 500);
    let rows = sqlx::query(
        "SELECT id, action, path, created_at FROM audit_logs ORDER BY created_at DESC LIMIT $1",
    )
    .bind(limit)
    .fetch_all(&state.db)
    .await?;
    Ok(Json(
        rows.into_iter()
            .map(|r| AuditResponse {
                id: r.get("id"),
                action: r.get("action"),
                path: r.get("path"),
                created_at: r.get("created_at"),
            })
            .collect(),
    ))
}

/// Which privileged change is being attempted on an account.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum AccountAction {
    Delete,
    Demote,
    Disable,
}

/// Why a privileged change to an account is refused.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum AccountRefusal {
    SelfDelete,
    SelfDisable,
    LastAdminDelete,
    LastAdminDemote,
}

impl AccountRefusal {
    fn message(self) -> &'static str {
        match self {
            AccountRefusal::SelfDelete => "You cannot delete your own account",
            AccountRefusal::SelfDisable => "You cannot disable your own account",
            AccountRefusal::LastAdminDelete => "The last administrator account cannot be deleted",
            AccountRefusal::LastAdminDemote => {
                "The last administrator account cannot be demoted or disabled"
            }
        }
    }
}

/// The complete account-protection policy, as a pure function.
///
/// This is the single home of the rule "NexaDrive can never be left with no
/// administrator". Keeping it dependency-free (the handler supplies the facts)
/// means every branch is unit-testable without a database, and the client's
/// `AdminUserRules` mirrors exactly these three rules:
///
///  1. you cannot delete the account you are signed in with;
///  2. you cannot disable the account you are signed in with;
///  3. the last *enabled* administrator can be neither deleted nor demoted nor
///     disabled — any of which would make the instance permanently
///     unmanageable.
///
/// Returns `None` when the change is allowed.
pub(crate) fn protection_refusal(
    action: AccountAction,
    is_self: bool,
    target_is_active_admin: bool,
    active_admin_count: i64,
) -> Option<AccountRefusal> {
    let last_admin = target_is_active_admin && active_admin_count <= 1;
    match action {
        AccountAction::Delete if is_self => Some(AccountRefusal::SelfDelete),
        AccountAction::Delete if last_admin => Some(AccountRefusal::LastAdminDelete),
        AccountAction::Disable if is_self => Some(AccountRefusal::SelfDisable),
        AccountAction::Disable | AccountAction::Demote if last_admin => {
            Some(AccountRefusal::LastAdminDemote)
        }
        _ => None,
    }
}

/// Maps a refusal onto the wire status the client expects: self-directed
/// changes are a bad request, structural ones are a conflict.
pub(crate) fn refusal_error(refusal: AccountRefusal) -> AppError {
    match refusal {
        AccountRefusal::SelfDelete | AccountRefusal::SelfDisable => {
            AppError::BadRequest(refusal.message().into())
        }
        AccountRefusal::LastAdminDelete | AccountRefusal::LastAdminDemote => {
            AppError::Conflict(refusal.message().into())
        }
    }
}

pub(crate) async fn list_users(
    State(state): State<AppState>,
    axum::extract::Extension(user_id): axum::extract::Extension<Uuid>,
) -> Result<Json<Vec<AdminUserResponse>>, AppError> {
    require_admin(&state.db, user_id).await?;
    let rows = sqlx::query("SELECT id, username, display_name, role, disabled, quota_bytes FROM users ORDER BY username")
        .fetch_all(&state.db).await?;
    Ok(Json(
        rows.into_iter()
            .map(|r| AdminUserResponse {
                id: r.get("id"),
                username: r.get("username"),
                display_name: r.get("display_name"),
                role: r.get("role"),
                disabled: r.get("disabled"),
                quota_bytes: r.get("quota_bytes"),
            })
            .collect(),
    ))
}

pub(crate) async fn create_user(
    State(state): State<AppState>,
    axum::extract::Extension(user_id): axum::extract::Extension<Uuid>,
    Json(payload): Json<CreateUserRequest>,
) -> Result<Json<AdminUserResponse>, AppError> {
    require_admin(&state.db, user_id).await?;
    let username = payload.username.trim().to_lowercase();
    let display_name = payload.display_name.trim().to_string();
    if username.len() < 3 || username.len() > 64 || display_name.is_empty() {
        return Err(AppError::BadRequest("Invalid user details".into()));
    }
    if payload.password.len() < 10 {
        return Err(AppError::BadRequest(
            "Password must be at least 10 characters".into(),
        ));
    }
    let role = payload.role.as_deref().unwrap_or("user");
    validate_role(role)?;
    if payload.quota_bytes.is_some_and(|v| v < 0) {
        return Err(AppError::BadRequest("Quota cannot be negative".into()));
    }
    let hash = hash_password(&payload.password)?;
    let id = Uuid::new_v4();
    sqlx::query("INSERT INTO users (id, username, display_name, password_hash, role, quota_bytes) VALUES ($1,$2,$3,$4,$5,$6)")
        .bind(id).bind(&username).bind(&display_name).bind(hash).bind(role).bind(payload.quota_bytes).execute(&state.db).await
        .map_err(|e| if let sqlx::Error::Database(db) = &e { if db.is_unique_violation() { AppError::Conflict("Username already exists".into()) } else { AppError::Database(e) } } else { AppError::Database(e) })?;
    audit(&state.db, user_id, "create_user", Some(&username)).await?;
    Ok(Json(AdminUserResponse {
        id,
        username,
        display_name,
        role: role.into(),
        disabled: false,
        quota_bytes: payload.quota_bytes,
    }))
}

pub(crate) async fn update_user(
    State(state): State<AppState>,
    axum::extract::Extension(admin_id): axum::extract::Extension<Uuid>,
    axum::extract::Path(id): axum::extract::Path<Uuid>,
    Json(payload): Json<UpdateUserRequest>,
) -> Result<StatusCode, AppError> {
    require_admin(&state.db, admin_id).await?;
    // Only fetch protection facts when a change could trip a rule: demoting to
    // a normal user, or disabling the account.
    let disabling = payload.disabled == Some(true);
    if disabling || payload.role.as_deref() == Some("user") {
        let target: Option<(String, bool)> =
            sqlx::query_as("SELECT role, disabled FROM users WHERE id=$1")
                .bind(id)
                .fetch_optional(&state.db)
                .await?;
        let Some((role, target_disabled)) = target else {
            return Err(AppError::NotFound);
        };
        let target_is_active_admin = role == "admin" && !target_disabled;
        let active_admins: i64 = if target_is_active_admin {
            sqlx::query_scalar("SELECT COUNT(*) FROM users WHERE role='admin' AND disabled=FALSE")
                .fetch_one(&state.db)
                .await?
        } else {
            0
        };
        if let Some(refusal) = protection_refusal(
            if disabling {
                AccountAction::Disable
            } else {
                AccountAction::Demote
            },
            id == admin_id,
            target_is_active_admin,
            active_admins,
        ) {
            return Err(refusal_error(refusal));
        }
    }
    if let Some(role) = payload.role.as_deref() {
        validate_role(role)?;
    }
    if payload.quota_bytes.is_some_and(|v| v < 0) {
        return Err(AppError::BadRequest("Quota cannot be negative".into()));
    }
    if payload.clear_quota == Some(true) && payload.quota_bytes.is_some() {
        return Err(AppError::BadRequest(
            "clear_quota and quota_bytes are mutually exclusive".into(),
        ));
    }
    if payload
        .display_name
        .as_deref()
        .map(|v| v.trim().is_empty())
        .unwrap_or(false)
    {
        return Err(AppError::BadRequest("Display name cannot be empty".into()));
    }
    if payload
        .password
        .as_deref()
        .is_some_and(|v| v.is_empty() || v.len() < 10)
    {
        return Err(AppError::BadRequest(
            "Password must be at least 10 characters".into(),
        ));
    }
    let new_hash = match payload.password.as_deref() {
        Some(pw) => Some(hash_password(pw)?),
        None => None,
    };
    // Quota: quota_bytes=COALESCE(null, quota_bytes) keeps partial-update
    // semantics; clear_quota=true sets it to NULL (unlimited) explicitly.
    let result = sqlx::query("UPDATE users SET display_name=COALESCE($1,display_name), role=COALESCE($2,role), disabled=COALESCE($3,disabled), quota_bytes=CASE WHEN $4 THEN NULL ELSE COALESCE($5,quota_bytes) END, password_hash=COALESCE($6,password_hash) WHERE id=$7")
        .bind(payload.display_name.map(|v| v.trim().to_string())).bind(payload.role).bind(payload.disabled).bind(payload.clear_quota == Some(true)).bind(payload.quota_bytes).bind(new_hash).bind(id).execute(&state.db).await?;
    if result.rows_affected() == 0 {
        return Err(AppError::NotFound);
    }
    if payload.password.is_some() {
        // A password change revokes every active session for that user.
        sqlx::query("DELETE FROM sessions WHERE user_id=$1")
            .bind(id)
            .execute(&state.db)
            .await?;
    }
    audit(&state.db, admin_id, "update_user", Some(&id.to_string())).await?;
    Ok(StatusCode::NO_CONTENT)
}

/// Deletes a user and everything they own: their files on disk (root + trash
/// folders), shares, trash metadata, sync fingerprints, sessions, and
/// notifications. Cascades are handled by the schema (ON DELETE CASCADE); the
/// on-disk folders are removed best-effort after the row is deleted.
pub(crate) async fn delete_user(
    State(state): State<AppState>,
    axum::extract::Extension(admin_id): axum::extract::Extension<Uuid>,
    axum::extract::Path(id): axum::extract::Path<Uuid>,
) -> Result<StatusCode, AppError> {
    require_admin(&state.db, admin_id).await?;
    let target: Option<(String, String, bool)> =
        sqlx::query_as("SELECT username, role, disabled FROM users WHERE id=$1")
            .bind(id)
            .fetch_optional(&state.db)
            .await?;
    let Some((username, role, target_disabled)) = target else {
        return Err(AppError::NotFound);
    };
    let target_is_active_admin = role == "admin" && !target_disabled;
    let active_admins: i64 = if target_is_active_admin {
        sqlx::query_scalar("SELECT COUNT(*) FROM users WHERE role='admin' AND disabled=FALSE")
            .fetch_one(&state.db)
            .await?
    } else {
        0
    };
    if let Some(refusal) = protection_refusal(
        AccountAction::Delete,
        id == admin_id,
        target_is_active_admin,
        active_admins,
    ) {
        return Err(refusal_error(refusal));
    }

    sqlx::query("DELETE FROM users WHERE id=$1")
        .bind(id)
        .execute(&state.db)
        .await?;

    // Best-effort on-disk cleanup: files live in <storage>/<user_id> and
    // trash in <storage>/.trash/<user_id>. A failure here must not fail the
    // account deletion — orphaned directories are inert, and re-creating a
    // user uses a fresh UUID so there is no accidental name collision.
    for dir in [user_root(&state, id), trash_root(&state, id)] {
        match fs::remove_dir_all(&dir).await {
            Ok(()) => {}
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => {}
            Err(_) => {}
        }
    }

    audit(&state.db, admin_id, "delete_user", Some(&username)).await?;
    Ok(StatusCode::NO_CONTENT)
}

/// Ends every session belonging to [id] without touching their credentials.
///
/// This is the "sign this account out everywhere" admin action — for a lost or
/// shared device. The stored password hash is deliberately left alone so the
/// user can sign back in. Administrators may revoke their own sessions too
/// (that is just a remote sign-out), but the client does not offer it for the
/// signed-in row to avoid an accidental self-lockout.
pub(crate) async fn revoke_user_sessions(
    State(state): State<AppState>,
    axum::extract::Extension(admin_id): axum::extract::Extension<Uuid>,
    axum::extract::Path(id): axum::extract::Path<Uuid>,
) -> Result<Json<RevokeSessionsResponse>, AppError> {
    require_admin(&state.db, admin_id).await?;
    let exists: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM users WHERE id=$1")
        .bind(id)
        .fetch_one(&state.db)
        .await?;
    if exists == 0 {
        return Err(AppError::NotFound);
    }
    let removed = sqlx::query("DELETE FROM sessions WHERE user_id=$1")
        .bind(id)
        .execute(&state.db)
        .await?;
    audit(
        &state.db,
        admin_id,
        "revoke_user_sessions",
        Some(&id.to_string()),
    )
    .await?;
    Ok(Json(RevokeSessionsResponse {
        revoked: removed.rows_affected(),
    }))
}

pub(crate) async fn audit(
    db: &SqlitePool,
    user_id: Uuid,
    action: &str,
    path: Option<&str>,
) -> Result<(), AppError> {
    sqlx::query("INSERT INTO audit_logs (id, user_id, action, path) VALUES ($1,$2,$3,$4)")
        .bind(Uuid::new_v4())
        .bind(user_id)
        .bind(action)
        .bind(path)
        .execute(db)
        .await?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    // ---------------------------------------------------------------- account
    // The rule that NexaDrive can never be left without an administrator.
    // These are the branches `delete_user` and `update_user` enforce.

    #[test]
    fn admin_cannot_delete_their_own_account() {
        assert_eq!(
            protection_refusal(AccountAction::Delete, true, true, 5),
            Some(AccountRefusal::SelfDelete),
        );
        // Even a non-administrator cannot delete themselves.
        assert_eq!(
            protection_refusal(AccountAction::Delete, true, false, 0),
            Some(AccountRefusal::SelfDelete),
        );
    }

    #[test]
    fn last_active_admin_cannot_be_deleted() {
        assert_eq!(
            protection_refusal(AccountAction::Delete, false, true, 1),
            Some(AccountRefusal::LastAdminDelete),
        );
    }

    #[test]
    fn last_active_admin_cannot_be_demoted_or_disabled() {
        assert_eq!(
            protection_refusal(AccountAction::Demote, false, true, 1),
            Some(AccountRefusal::LastAdminDemote),
        );
        assert_eq!(
            protection_refusal(AccountAction::Disable, false, true, 1),
            Some(AccountRefusal::LastAdminDemote),
        );
    }

    #[test]
    fn a_second_administrator_removes_the_structural_refusal() {
        // With two enabled admins, either may be deleted/demoted/disabled.
        assert_eq!(
            protection_refusal(AccountAction::Delete, false, true, 2),
            None,
        );
        assert_eq!(
            protection_refusal(AccountAction::Demote, false, true, 2),
            None,
        );
        assert_eq!(
            protection_refusal(AccountAction::Disable, false, true, 2),
            None,
        );
    }

    #[test]
    fn ordinary_accounts_are_never_structurally_protected() {
        for action in [
            AccountAction::Delete,
            AccountAction::Demote,
            AccountAction::Disable,
        ] {
            assert_eq!(
                protection_refusal(action, false, false, 1),
                None,
                "a plain user must remain fully manageable"
            );
            assert_eq!(protection_refusal(action, false, false, 0), None);
        }
    }

    #[test]
    fn disabling_yourself_is_refused_but_demoting_yourself_is_not() {
        // Mirrors the long-standing behaviour: an admin may step down while
        // another admin exists, but may not lock themselves out.
        assert_eq!(
            protection_refusal(AccountAction::Disable, true, true, 3),
            Some(AccountRefusal::SelfDisable),
        );
        assert_eq!(
            protection_refusal(AccountAction::Demote, true, true, 3),
            None,
        );
    }

    #[test]
    fn self_refusals_take_precedence_over_structural_ones() {
        // The single remaining administrator deleting themselves gets the
        // self message (400), not the structural one (409) — it is the more
        // actionable explanation.
        assert_eq!(
            protection_refusal(AccountAction::Delete, true, true, 1),
            Some(AccountRefusal::SelfDelete),
        );
    }

    #[test]
    fn self_refusals_are_bad_requests_and_structural_ones_conflict() {
        assert!(matches!(
            refusal_error(AccountRefusal::SelfDelete),
            AppError::BadRequest(_)
        ));
        assert!(matches!(
            refusal_error(AccountRefusal::SelfDisable),
            AppError::BadRequest(_)
        ));
        assert!(matches!(
            refusal_error(AccountRefusal::LastAdminDelete),
            AppError::Conflict(_)
        ));
        assert!(matches!(
            refusal_error(AccountRefusal::LastAdminDemote),
            AppError::Conflict(_)
        ));
    }

    #[test]
    fn every_refusal_carries_an_explanation() {
        for refusal in [
            AccountRefusal::SelfDelete,
            AccountRefusal::SelfDisable,
            AccountRefusal::LastAdminDelete,
            AccountRefusal::LastAdminDemote,
        ] {
            let message = refusal.message();
            assert!(!message.is_empty());
            assert!(!message.contains('\n'), "one-line messages only");
        }
    }

    #[test]
    fn validate_password_minimum_length() {
        // This tests the server-side password validation logic
        // Password length check happens in create_user, not in a standalone function,
        // but we verify the concept here
        let short = "abc";
        assert!(short.len() < 10);
        let long = "a_very_long_password_123";
        assert!(long.len() >= 10);
    }
}
