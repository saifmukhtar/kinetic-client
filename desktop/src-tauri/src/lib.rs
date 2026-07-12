mod installer;

use tauri::{
    menu::{Menu, MenuItem, PredefinedMenuItem},
    tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent},
    Manager,
};

// Learn more about Tauri commands at https://tauri.app/develop/calling-rust/
#[tauri::command]
fn greet(name: &str) -> String {
    format!("Hello, {}! You've been greeted from Rust!", name)
}

#[tauri::command]
fn get_api_token() -> Result<String, String> {
    let token_path = kinetic_core::config::get_base_dir().join("api.token");
    std::fs::read_to_string(token_path)
        .map(|s| s.trim().to_string())
        .map_err(|e| format!("Failed to read API token: {}", e))
}

#[tauri::command]
fn generate_seed() -> Result<String, String> {
    use bip39::{Language, Mnemonic};
    use getrandom::getrandom;

    let mut entropy = [0u8; 32];
    getrandom(&mut entropy).map_err(|e| format!("Failed to generate random entropy: {}", e))?;
    let mnemonic = Mnemonic::from_entropy_in(Language::English, &entropy)
        .map_err(|e| format!("Failed to generate mnemonic: {}", e))?;
    
    Ok(mnemonic.to_string())
}

#[tauri::command]
fn save_identity(phrase: String) -> Result<(), String> {
    kinetic_core::types::save_keypair_from_mnemonic("identity.key", &phrase)
        .map_err(|e| format!("Failed to save identity: {}", e))?;
    
    // Attempt to restart the service to pick up the new identity
    use std::process::Command;
    let _ = Command::new("kinetic-daemon")
        .arg("stop-service")
        .output();
    let _ = Command::new("kinetic-daemon")
        .arg("start-service")
        .output();
        
    Ok(())
}

fn show_main_window(app: &tauri::AppHandle) {
    if let Some(window) = app.get_webview_window("main") {
        let _ = window.show();
        let _ = window.unminimize();
        let _ = window.set_focus();
    }
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .setup(|app| {
            let show = MenuItem::with_id(app, "show", "Show Kinetic", true, None::<&str>)?;
            let hide = MenuItem::with_id(app, "hide", "Hide Window", true, None::<&str>)?;
            let quit = MenuItem::with_id(app, "quit", "Quit Kinetic", true, None::<&str>)?;
            let separator = PredefinedMenuItem::separator(app)?;
            let menu = Menu::with_items(app, &[&show, &hide, &separator, &quit])?;

            TrayIconBuilder::with_id("kinetic")
                .tooltip("Kinetic")
                .icon(app.default_window_icon().cloned().expect("missing app icon"))
                .menu(&menu)
                .show_menu_on_left_click(false)
                .on_menu_event(|app, event| match event.id().as_ref() {
                    "show" => show_main_window(app),
                    "hide" => {
                        if let Some(window) = app.get_webview_window("main") {
                            let _ = window.hide();
                        }
                    }
                    "quit" => app.exit(0),
                    _ => {}
                })
                .on_tray_icon_event(|tray, event| match event {
                    TrayIconEvent::Click {
                        button: MouseButton::Left,
                        button_state: MouseButtonState::Up,
                        ..
                    }
                    | TrayIconEvent::DoubleClick {
                        button: MouseButton::Left,
                        ..
                    } => show_main_window(tray.app_handle()),
                    _ => {}
                })
                .build(app)?;

            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            greet,
            get_api_token,
            generate_seed,
            save_identity,
            installer::install_profile
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
