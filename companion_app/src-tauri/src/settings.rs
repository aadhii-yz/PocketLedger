use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use std::sync::Mutex;
use tauri::Manager;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Settings {
    pub pocketledger_url: String,
    pub barcode_ip: String,
    pub barcode_port: u16,
    pub receipt_ip: String,
    pub receipt_port: u16,
    pub server_port: u16,
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            pocketledger_url: String::new(),
            barcode_ip: String::new(),
            barcode_port: 9100,
            receipt_ip: String::new(),
            receipt_port: 9100,
            server_port: 8765,
        }
    }
}

pub struct SettingsState(pub Mutex<Settings>);

fn settings_path(app: &tauri::AppHandle) -> PathBuf {
    app.path()
        .app_data_dir()
        .unwrap_or_else(|_| PathBuf::from("."))
        .join("settings.json")
}

pub fn load_settings(app: &tauri::AppHandle) -> Settings {
    let path = settings_path(app);
    std::fs::read_to_string(&path)
        .ok()
        .and_then(|s| serde_json::from_str(&s).ok())
        .unwrap_or_default()
}

fn write_settings(app: &tauri::AppHandle, settings: &Settings) -> Result<(), String> {
    let path = settings_path(app);
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    }
    let json = serde_json::to_string_pretty(settings).map_err(|e| e.to_string())?;
    std::fs::write(&path, json).map_err(|e| e.to_string())
}

#[tauri::command]
pub fn get_settings(
    state: tauri::State<std::sync::Arc<SettingsState>>,
) -> Settings {
    state.0.lock().unwrap().clone()
}

#[tauri::command]
pub fn save_settings(
    app: tauri::AppHandle,
    state: tauri::State<std::sync::Arc<SettingsState>>,
    settings: Settings,
) -> Result<(), String> {
    write_settings(&app, &settings)?;
    *state.0.lock().unwrap() = settings;
    Ok(())
}
