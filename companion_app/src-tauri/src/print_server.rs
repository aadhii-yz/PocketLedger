use crate::escpos::{print_receipt, ReceiptData};
use crate::settings::SettingsState;
use crate::tspl::{print_barcode, BarcodeData};
use axum::{
    extract::State,
    http::{Method, StatusCode},
    response::Json,
    routing::{get, post},
    Router,
};
use serde_json::{json, Value};
use std::sync::Arc;
use tower_http::cors::{Any, CorsLayer};

pub async fn start(state: Arc<SettingsState>, port: u16) {
    let cors = CorsLayer::new()
        .allow_origin(Any)
        .allow_methods([Method::GET, Method::POST])
        .allow_headers(Any);

    let app = Router::new()
        .route("/status", get(status))
        .route("/print/barcode", post(handle_barcode))
        .route("/print/receipt", post(handle_receipt))
        .layer(cors)
        .with_state(state);

    let addr = format!("127.0.0.1:{port}");
    let listener = tokio::net::TcpListener::bind(&addr).await.unwrap();
    axum::serve(listener, app).await.unwrap();
}

async fn status() -> Json<Value> {
    Json(json!({ "ok": true, "version": "1.0.0" }))
}

async fn handle_barcode(
    State(state): State<Arc<SettingsState>>,
    Json(data): Json<BarcodeData>,
) -> (StatusCode, Json<Value>) {
    let settings = state.0.lock().unwrap().clone();
    if settings.barcode_ip.is_empty() {
        return (
            StatusCode::UNPROCESSABLE_ENTITY,
            Json(json!({ "error": "Barcode printer IP not configured" })),
        );
    }
    match print_barcode(&settings.barcode_ip, settings.barcode_port, &data) {
        Ok(()) => (StatusCode::OK, Json(json!({ "ok": true }))),
        Err(e) => (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(json!({ "error": e })),
        ),
    }
}

async fn handle_receipt(
    State(state): State<Arc<SettingsState>>,
    Json(data): Json<ReceiptData>,
) -> (StatusCode, Json<Value>) {
    let settings = state.0.lock().unwrap().clone();
    if settings.receipt_ip.is_empty() {
        return (
            StatusCode::UNPROCESSABLE_ENTITY,
            Json(json!({ "error": "Receipt printer IP not configured" })),
        );
    }
    match print_receipt(&settings.receipt_ip, settings.receipt_port, &data) {
        Ok(()) => (StatusCode::OK, Json(json!({ "ok": true }))),
        Err(e) => (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(json!({ "error": e })),
        ),
    }
}
