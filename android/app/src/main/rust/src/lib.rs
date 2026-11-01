use std::{
    path::Path,
    sync::{
        atomic::{AtomicBool, Ordering},
        Mutex, OnceLock,
    },
    thread,
};

use futures_util::StreamExt;
use jni::{objects::{JObject, JString}, JNIEnv};
use librespot::{
    connect::{ConnectConfig, Spirc},
    core::{cache::Cache, config::{DeviceType, SessionConfig}, session::Session},
    discovery::Discovery,
    playback::{
        audio_backend,
        config::{AudioFormat, PlayerConfig},
        mixer::{self, MixerConfig},
        player::Player,
    },
};
use tokio::sync::watch;

static STATUS: OnceLock<Mutex<String>> = OnceLock::new();
static STOP: OnceLock<Mutex<Option<watch::Sender<bool>>>> = OnceLock::new();
static RUNNING: AtomicBool = AtomicBool::new(false);
static ANDROID_CONTEXT_READY: AtomicBool = AtomicBool::new(false);

fn status() -> &'static Mutex<String> {
    STATUS.get_or_init(|| Mutex::new("Mati".to_owned()))
}

fn set_status(value: impl Into<String>) {
    if let Ok(mut current) = status().lock() {
        *current = value.into();
    }
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_com_swiftmusic_swift_1music_SpotifyConnectService_nativeSpotifyStart(
    mut env: JNIEnv,
    _activity: JObject,
    context: JObject,
    cache_path: JString,
) -> jni::sys::jboolean {
    if RUNNING.swap(true, Ordering::SeqCst) {
        return jni::sys::JNI_TRUE;
    }
    let setup = (|| -> Result<(String, jni::JavaVM), String> {
        let path: String = env
            .get_string(&cache_path)
            .map_err(|e| e.to_string())?
            .into();
        let vm = env.get_java_vm().map_err(|e| e.to_string())?;
        if !ANDROID_CONTEXT_READY.swap(true, Ordering::SeqCst) {
            let context = env.new_global_ref(context).map_err(|e| e.to_string())?;
            unsafe {
                ndk_context::initialize_android_context(
                    vm.get_java_vm_pointer().cast(),
                    context.as_obj().as_raw().cast(),
                );
            }
            std::mem::forget(context);
        }
        Ok((path, vm))
    })();
    let (cache_path, _vm) = match setup {
        Ok(values) => values,
        Err(error) => {
            RUNNING.store(false, Ordering::SeqCst);
            set_status(format!("Gagal menyiapkan Android audio: {error}"));
            return jni::sys::JNI_FALSE;
        }
    };

    let (stop_tx, stop_rx) = watch::channel(false);
    if let Ok(mut slot) = STOP.get_or_init(|| Mutex::new(None)).lock() {
        *slot = Some(stop_tx);
    }
    set_status("Menyiapkan Spotify Connect…");
    thread::spawn(move || {
        let result = tokio::runtime::Builder::new_multi_thread()
            .enable_all()
            .build()
            .map_err(|e| e.to_string())
            .and_then(|runtime| runtime.block_on(run_receiver(cache_path, stop_rx)).map_err(|e| e.to_string()));
        RUNNING.store(false, Ordering::SeqCst);
        match result {
            Ok(()) => set_status("Mati"),
            Err(error) => set_status(format!("Spotify Connect berhenti: {error}")),
        }
    });
    jni::sys::JNI_TRUE
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_com_swiftmusic_swift_1music_SpotifyConnectService_nativeSpotifyStop(
    _env: JNIEnv,
    _activity: JObject,
) {
    if let Ok(mut slot) = STOP.get_or_init(|| Mutex::new(None)).lock() {
        if let Some(sender) = slot.take() {
            let _ = sender.send(true);
        }
    }
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_com_swiftmusic_swift_1music_MainActivity_nativeSpotifyStatus(
    env: JNIEnv,
    _activity: JObject,
) -> jstring {
    let message = status().lock().map(|s| s.clone()).unwrap_or_default();
    env.new_string(message)
        .map(|value| value.into_raw())
        .unwrap_or(std::ptr::null_mut())
}

use jni::sys::jstring;

async fn run_receiver(
    cache_path: String,
    mut stop: watch::Receiver<bool>,
) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let session_config = SessionConfig::default();
    let cache_dir = Path::new(&cache_path);
    std::fs::create_dir_all(cache_dir)?;
    let audio_dir = cache_dir.join("audio");
    let cache = Cache::new(
        Some(cache_dir),
        Some(cache_dir),
        Some(audio_dir.as_path()),
        Some(512 * 1024 * 1024),
    )?;
    let connect_config = ConnectConfig {
        name: "Swift Music".to_owned(),
        device_type: DeviceType::Speaker,
        ..ConnectConfig::default()
    };
    let discovery = Discovery::builder(session_config.device_id.clone(), session_config.client_id.clone())
        .name(connect_config.name.clone())
        .device_type(DeviceType::Speaker)
        .launch()?;
    let backend = audio_backend::find(None).ok_or("No Android audio backend")?;
    let mixer_builder = mixer::find(None).ok_or("No volume mixer")?;
    let mixer = mixer_builder(MixerConfig::default())?;
    let player = Player::new(
        PlayerConfig::default(),
        Session::new(session_config.clone(), Some(cache.clone())),
        mixer.get_soft_volume(),
        move || backend(None, AudioFormat::default()),
    );
    let mut discovery = discovery;
    let mut session = Session::new(session_config.clone(), Some(cache.clone()));
    let mut spirc: Option<Spirc> = None;
    let mut spirc_task: Option<tokio::task::JoinHandle<()>> = None;
    set_status("Siap · buka Spotify dan pilih perangkat Swift Music");

    loop {
        tokio::select! {
            _ = stop.changed() => {
                if *stop.borrow() { break; }
            }
            credentials = discovery.next() => {
                let Some(credentials) = credentials else {
                    return Err(std::io::Error::other("Spotify Connect discovery berhenti").into());
                };
                cache.save_credentials(&credentials);
                if let Some(old) = spirc.take() { let _ = old.shutdown(); }
                if let Some(task) = spirc_task.take() { task.abort(); }
                if !session.is_invalid() { session.shutdown(); }
                session = Session::new(session_config.clone(), Some(cache.clone()));
                player.set_session(session.clone());
                let (controller, task) = Spirc::new(
                    connect_config.clone(), session.clone(), credentials, player.clone(), mixer.clone(),
                ).await?;
                spirc = Some(controller);
                spirc.as_ref().expect("controller inserted").activate()?;
                spirc_task = Some(tokio::spawn(task));
                set_status("Terhubung · pemutaran dikendalikan Spotify Connect");
            }
            result = async {
                match spirc_task.as_mut() {
                    Some(task) => task.await,
                    None => std::future::pending().await,
                }
            } => {
                let _ = result;
                spirc_task = None;
                spirc = None;
                set_status("Siap · buka Spotify dan pilih perangkat Swift Music");
            }
        }
    }
    if let Some(controller) = spirc { let _ = controller.shutdown(); }
    if let Some(task) = spirc_task { task.abort(); }
    player.stop();
    discovery.shutdown().await;
    Ok(())
}
