use axum::{Json, extract::State};

use crate::{
    API_VERSION,
    models::{Health, ServerStatus},
    state::AppState,
};

pub(crate) async fn health() -> Json<Health> {
    Json(Health { status: "ok" })
}

pub(crate) async fn server_status(State(state): State<AppState>) -> Json<ServerStatus> {
    Json(ServerStatus {
        instance_id: state.instance_id,
        started_at: state.started_at,
        status: "ok",
        public_url: state.public_url.clone(),
        version: env!("CARGO_PKG_VERSION"),
        api_version: API_VERSION,
    })
}
