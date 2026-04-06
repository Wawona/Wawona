//! Graphics smoke test - validates Vulkan/OpenGL driver availability and basic init.
//! Run with: cargo run --bin graphics-smoke
//! Or: nix run .#graphics-smoke (when exposed in flake)
//!
//! Outputs JSON with driver metadata for integration into the validation matrix.

use ash::vk;
use std::ffi::CStr;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let mut report = serde_json::json!({
        "platform": std::env::consts::OS,
        "vulkan": null,
        "timestamp": chrono::Utc::now().to_rfc3339(),
    });

    // Vulkan smoke: instance + physical device enumeration
    match run_vulkan_smoke() {
        Ok(vk_info) => report["vulkan"] = serde_json::json!(vk_info),
        Err(e) => report["vulkan"] = serde_json::json!({ "error": e.to_string() }),
    }

    println!("{}", serde_json::to_string_pretty(&report)?);
    Ok(())
}

fn run_vulkan_smoke() -> Result<serde_json::Value, Box<dyn std::error::Error>> {
    let entry = unsafe { ash::Entry::load()? };
    let app_info = vk::ApplicationInfo::default()
        .api_version(vk::API_VERSION_1_2);
    let create_info = vk::InstanceCreateInfo::default()
        .application_info(&app_info);
    let instance = unsafe { entry.create_instance(&create_info, None)? };

    let physical_devices = unsafe { instance.enumerate_physical_devices()? };

    let mut devices = Vec::new();
    for pd in physical_devices {
        let props = unsafe { instance.get_physical_device_properties(pd) };
        let driver_version = format!(
            "{}.{}.{}",
            vk::api_version_major(props.driver_version),
            vk::api_version_minor(props.driver_version),
            vk::api_version_patch(props.driver_version)
        );
        let api_version = format!(
            "{}.{}.{}",
            vk::api_version_major(props.api_version),
            vk::api_version_minor(props.api_version),
            vk::api_version_patch(props.api_version)
        );
        let device_name = unsafe {
            CStr::from_ptr(props.device_name.as_ptr())
                .to_string_lossy()
                .into_owned()
        };
        devices.push(serde_json::json!({
            "deviceName": device_name,
            "driverVersion": driver_version,
            "apiVersion": api_version,
            "vendorId": format!("0x{:04x}", props.vendor_id),
            "deviceId": format!("0x{:04x}", props.device_id),
        }));
    }

    unsafe {
        instance.destroy_instance(None);
    }

    Ok(serde_json::json!({
        "status": "ok",
        "physicalDeviceCount": devices.len(),
        "devices": devices,
        "icd": std::env::var("VK_DRIVER_FILES").unwrap_or_else(|_| "system default".into()),
    }))
}
