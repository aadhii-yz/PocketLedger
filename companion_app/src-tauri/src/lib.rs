mod escpos;
mod print_server;
mod settings;
mod tspl;

use escpos::ReceiptData;
use settings::{get_settings, load_settings, save_settings, SettingsState};
use std::sync::{Arc, Mutex};
use tauri::Manager;
use tspl::BarcodeData;

#[tauri::command]
fn print_barcode_cmd(
    state: tauri::State<Arc<SettingsState>>,
    data: BarcodeData,
) -> Result<(), String> {
    let s = state.0.lock().unwrap().clone();
    if s.barcode_ip.is_empty() {
        return Err("Barcode printer IP not configured".into());
    }
    tspl::print_barcode(&s.barcode_ip, s.barcode_port, &data)
}

#[tauri::command]
fn print_receipt_cmd(
    state: tauri::State<Arc<SettingsState>>,
    data: ReceiptData,
) -> Result<(), String> {
    let s = state.0.lock().unwrap().clone();
    if s.receipt_ip.is_empty() {
        return Err("Receipt printer IP not configured".into());
    }
    escpos::print_receipt(&s.receipt_ip, s.receipt_port, &data)
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .setup(|app| {
            let settings = load_settings(app.handle());
            let port = settings.server_port;
            let shared = Arc::new(SettingsState(Mutex::new(settings)));

            let server_state = Arc::clone(&shared);
            tauri::async_runtime::spawn(async move {
                print_server::start(server_state, port).await;
            });

            app.manage(shared);
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            get_settings,
            save_settings,
            print_barcode_cmd,
            print_receipt_cmd,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
