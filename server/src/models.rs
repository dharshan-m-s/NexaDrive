use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Serialize)]
pub(crate) struct Health {
    pub(crate) status: &'static str,
}

#[derive(Serialize)]
pub(crate) struct ServerStatus {
    pub(crate) instance_id: Uuid,
    pub(crate) started_at: DateTime<Utc>,
    pub(crate) status: &'static str,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub(crate) public_url: Option<String>,
    /// Server release version (Cargo package version). Sent in every status
    /// response so clients can warn about incompatible server deployments.
    pub(crate) version: &'static str,
    /// Backward-compatibility contract: the API surface this build speaks.
    pub(crate) api_version: &'static str,
}

#[derive(Serialize)]
pub(crate) struct NotificationResponse {
    pub(crate) id: Uuid,
    pub(crate) kind: String,
    pub(crate) title: String,
    pub(crate) message: String,
    pub(crate) severity: String,
    pub(crate) read: bool,
    pub(crate) created_at: DateTime<Utc>,
}

#[derive(Deserialize)]
pub(crate) struct NotificationReadRequest {
    pub(crate) id: Option<Uuid>,
    pub(crate) all: Option<bool>,
}

#[derive(Serialize)]
pub(crate) struct AuditResponse {
    pub(crate) id: Uuid,
    pub(crate) action: String,
    pub(crate) path: Option<String>,
    pub(crate) created_at: DateTime<Utc>,
}

#[derive(Serialize)]
pub(crate) struct SyncDeviceResponse {
    pub(crate) id: Uuid,
    pub(crate) name: String,
    /// "android" | "windows" | "linux" | "macos", or null for devices that
    /// registered before the platform column existed.
    pub(crate) platform: Option<String>,
    pub(crate) last_seen_at: DateTime<Utc>,
    pub(crate) created_at: DateTime<Utc>,
}

#[derive(Deserialize)]
pub(crate) struct BackupRestoreRequest {
    pub(crate) snapshot_id: String,
}

#[derive(Serialize)]
pub(crate) struct BackupSnapshotResponse {
    pub(crate) id: String,
    pub(crate) time: DateTime<Utc>,
    pub(crate) hostname: Option<String>,
    pub(crate) paths: Vec<String>,
}

#[derive(Deserialize)]
pub(crate) struct LoginRequest {
    pub(crate) username: String,
    pub(crate) password: String,
}

#[derive(Serialize)]
pub(crate) struct LoginResponse {
    pub(crate) token: String,
    pub(crate) user: UserResponse,
}

#[derive(Serialize)]
pub(crate) struct UserResponse {
    pub(crate) id: Uuid,
    pub(crate) username: String,
    pub(crate) display_name: String,
    pub(crate) role: String,
}

#[derive(Serialize)]
pub(crate) struct RevokeSessionsResponse {
    pub(crate) revoked: u64,
}

#[derive(Serialize)]
pub(crate) struct AdminUserResponse {
    pub(crate) id: Uuid,
    pub(crate) username: String,
    pub(crate) display_name: String,
    pub(crate) role: String,
    pub(crate) disabled: bool,
    pub(crate) quota_bytes: Option<i64>,
}

#[derive(Deserialize)]
pub(crate) struct CreateUserRequest {
    pub(crate) username: String,
    pub(crate) display_name: String,
    pub(crate) password: String,
    pub(crate) role: Option<String>,
    pub(crate) quota_bytes: Option<i64>,
}

#[derive(Deserialize)]
pub(crate) struct UpdateUserRequest {
    pub(crate) display_name: Option<String>,
    pub(crate) role: Option<String>,
    pub(crate) disabled: Option<bool>,
    pub(crate) quota_bytes: Option<i64>,
    /// When true, `quota_bytes` is applied even when it is null, clearing the
    /// quota back to unlimited. Without this flag a null/omitted quota_bytes
    /// leaves the stored value untouched (partial-update semantics).
    pub(crate) clear_quota: Option<bool>,
    /// Optional new password. When present, the password is re-hashed and the
    /// user's existing sessions are revoked (a password change invalidates
    /// every active session as a security baseline).
    pub(crate) password: Option<String>,
}

#[derive(Serialize)]
pub(crate) struct ShareResponse {
    pub(crate) id: Uuid,
    pub(crate) path: String,
    pub(crate) permission: String,
    pub(crate) recipient: Option<String>,
    pub(crate) is_link: bool,
    pub(crate) token: Option<String>,
    pub(crate) expires_at: Option<DateTime<Utc>>,
}

#[derive(Deserialize)]
pub(crate) struct CreateShareRequest {
    pub(crate) path: String,
    pub(crate) username: Option<String>,
    pub(crate) permission: String,
    pub(crate) expires_at: Option<DateTime<Utc>>,
}

#[derive(Deserialize)]
pub(crate) struct SharedQuery {
    pub(crate) share_id: Uuid,
    pub(crate) path: Option<String>,
}

#[derive(Deserialize)]
pub(crate) struct SharedActionRequest {
    pub(crate) share_id: Uuid,
    pub(crate) action: String,
    pub(crate) path: String,
    pub(crate) name: Option<String>,
    pub(crate) destination: Option<String>,
}

#[derive(Serialize)]
pub(crate) struct SharedRootResponse {
    pub(crate) id: Uuid,
    pub(crate) name: String,
    pub(crate) path: String,
    pub(crate) permission: String,
    pub(crate) owner: String,
}

#[derive(Serialize)]
pub(crate) struct FileEntry {
    pub(crate) name: String,
    pub(crate) path: String,
    pub(crate) kind: String,
    pub(crate) size: i64,
    pub(crate) modified_at: Option<DateTime<Utc>>,
}

#[derive(Serialize)]
pub(crate) struct TrashEntry {
    pub(crate) id: Uuid,
    pub(crate) name: String,
    pub(crate) original_path: String,
    pub(crate) kind: String,
    pub(crate) size: i64,
    pub(crate) deleted_at: DateTime<Utc>,
}

#[derive(Deserialize)]
pub(crate) struct PathQuery {
    pub(crate) path: Option<String>,
}

#[derive(Deserialize)]
pub(crate) struct ThumbQuery {
    pub(crate) path: Option<String>,
    pub(crate) max: Option<u32>,
}

#[derive(Deserialize)]
pub(crate) struct SearchQuery {
    pub(crate) q: String,
}

#[derive(Deserialize)]
pub(crate) struct RenameRequest {
    pub(crate) source: String,
    pub(crate) name: String,
}

#[derive(Deserialize)]
pub(crate) struct TransferRequest {
    pub(crate) source: String,
    pub(crate) destination: String,
}

#[derive(Deserialize)]
pub(crate) struct BatchRequest {
    pub(crate) action: String,
    pub(crate) paths: Vec<String>,
    pub(crate) destination: Option<String>,
}

#[derive(Serialize)]
pub(crate) struct ActionResponse {
    pub(crate) path: String,
}

#[derive(Deserialize)]
pub(crate) struct IdQuery {
    pub(crate) id: Option<Uuid>,
}

#[derive(Deserialize)]
pub(crate) struct CreateFolderRequest {
    pub(crate) path: String,
}

#[derive(Serialize)]
pub(crate) struct StorageResponse {
    pub(crate) used_bytes: u64,
    pub(crate) file_count: u64,
}

#[derive(Serialize)]
pub(crate) struct PhotoEntry {
    pub(crate) name: String,
    pub(crate) path: String,
    pub(crate) size: i64,
    pub(crate) modified_at: Option<DateTime<Utc>>,
}

#[derive(Deserialize)]
pub(crate) struct UploadStatusQuery {
    pub(crate) upload_id: Uuid,
}

#[derive(Deserialize)]
pub(crate) struct ChunkQuery {
    pub(crate) upload_id: Uuid,
    pub(crate) path: String,
    pub(crate) name: String,
    pub(crate) offset: u64,
    pub(crate) total: u64,
}

#[derive(Deserialize)]
pub(crate) struct SyncManifestQuery {
    pub(crate) device_id: Option<Uuid>,
    pub(crate) device_name: Option<String>,
    pub(crate) platform: Option<String>,
}

#[derive(Deserialize)]
pub(crate) struct SyncDeltaQuery {
    pub(crate) device_id: Option<Uuid>,
    pub(crate) device_name: Option<String>,
    pub(crate) platform: Option<String>,
    pub(crate) since: String,
}

#[derive(Deserialize)]
pub(crate) struct RenameDeviceRequest {
    pub(crate) id: Uuid,
    pub(crate) name: String,
}

#[derive(Deserialize)]
#[allow(dead_code)]
pub(crate) struct SyncDeleteRequest {
    pub(crate) path: String,
    pub(crate) device_id: Option<Uuid>,
}

#[derive(Deserialize)]
pub(crate) struct BackupRunRequest {
    pub(crate) prune: Option<bool>,
}

#[derive(Serialize)]
pub(crate) struct BackupStatusResponse {
    pub(crate) configured: bool,
    pub(crate) restic_available: bool,
    pub(crate) repository: Option<String>,
}

#[derive(Serialize)]
pub(crate) struct BackupRunResponse {
    pub(crate) output: String,
}

#[derive(Serialize)]
pub(crate) struct BackupCheckResponse {
    pub(crate) output: String,
    pub(crate) verified: bool,
}

#[derive(Serialize)]
pub(crate) struct SyncEntry {
    pub(crate) path: String,
    pub(crate) kind: String,
    pub(crate) size: u64,
    pub(crate) modified_at: Option<DateTime<Utc>>,
    pub(crate) sha256: Option<String>,
}

#[derive(Serialize)]
pub(crate) struct SyncManifestResponse {
    pub(crate) device_id: Uuid,
    pub(crate) server_time: DateTime<Utc>,
    pub(crate) entries: Vec<SyncEntry>,
    pub(crate) tombstones: Vec<String>,
}
