mod escpos;
mod print_server;
mod settings;
mod tspl;

use escpos::ReceiptData;
use settings::{get_settings, load_settings, save_settings, SettingsState};
use std::sync::{Arc, Mutex};
use tauri::{
    plugin::{Builder as PluginBuilder, TauriPlugin},
    AppHandle, Manager, Runtime,
};
use tspl::BarcodeData;

#[cfg(target_os = "android")]
use tauri::plugin::PluginHandle;

/// Wraps the registered Android `PrintPlugin` handle so app commands can
/// drive the foreground service. Only present on Android.
#[cfg(target_os = "android")]
struct PrintPlugin<R: Runtime>(PluginHandle<R>);

/// Internal Tauri plugin whose only job is to register the Kotlin
/// `PrintPlugin` (`com.pocketledger.companion.PrintPlugin`) on Android and
/// stash its handle in managed state. It exposes no JS-invokable commands,
/// so it needs no ACL capability entry.
fn init_print<R: Runtime>() -> TauriPlugin<R> {
    PluginBuilder::new("print-service")
        .setup(|_app, _api| {
            #[cfg(target_os = "android")]
            {
                let handle =
                    _api.register_android_plugin("com.pocketledger.companion", "PrintPlugin")?;
                _app.manage(PrintPlugin(handle));
            }
            Ok(())
        })
        .build()
}

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

/// Starts the Android foreground service that keeps the local print server
/// (`localhost:8765`) alive when the user switches away from the app.
/// No-op on desktop.
#[tauri::command]
fn start_print_service<R: Runtime>(_app: AppHandle<R>) -> Result<(), String> {
    #[cfg(target_os = "android")]
    {
        let plugin = _app.state::<PrintPlugin<R>>();
        plugin
            .0
            .run_mobile_plugin::<serde_json::Value>("startService", ())
            .map_err(|e| e.to_string())?;
    }
    Ok(())
}

/// Stops the Android foreground service. No-op on desktop.
#[tauri::command]
fn stop_print_service<R: Runtime>(_app: AppHandle<R>) -> Result<(), String> {
    #[cfg(target_os = "android")]
    {
        let plugin = _app.state::<PrintPlugin<R>>();
        plugin
            .0
            .run_mobile_plugin::<serde_json::Value>("stopService", ())
            .map_err(|e| e.to_string())?;
    }
    Ok(())
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(init_print())
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
            start_print_service,
            stop_print_service,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
