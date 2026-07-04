//! # Media Handling Module
//!
//! This module manages incoming and outgoing WebSocket media streams. It handles the parsing
//! and forwarding of binary video and audio frames between clients and the agent broadcaster.

use axum::extract::ws::{Message, WebSocket};
use futures::{SinkExt, StreamExt};
use tokio::sync::broadcast;
use tracing::{error, info, warn};

/// Handle an incoming WebSocket connection for live video.
///
/// Receives raw binary video frames from the client and broadcasts them via the internal video broadcast channel.
pub async fn handle_video_stream(
    socket: WebSocket,
    video_tx: broadcast::Sender<Vec<u8>>,
) {
    let (mut _sink, mut stream) = socket.split();
    info!("Live video stream connected");

    while let Some(msg) = stream.next().await {
        match msg {
            Ok(Message::Binary(data)) => {
                if let Err(e) = video_tx.send(data.to_vec()) {
                    warn!("No video subscribers: {}", e);
                }
            }
            Ok(Message::Close(_)) => {
                info!("Video stream closed");
                break;
            }
            Err(e) => {
                error!("Video stream error: {}", e);
                break;
            }
            _ => {}
        }
    }
}

/// Handle an incoming WebSocket connection for live audio.
///
/// Receives raw binary audio frames from the client and broadcasts them via the internal audio broadcast channel.
pub async fn handle_audio_stream(
    socket: WebSocket,
    audio_tx: broadcast::Sender<Vec<u8>>,
) {
    let (mut _sink, mut stream) = socket.split();
    info!("Live audio stream connected");

    while let Some(msg) = stream.next().await {
        match msg {
            Ok(Message::Binary(data)) => {
                if let Err(e) = audio_tx.send(data.to_vec()) {
                    warn!("No audio subscribers: {}", e);
                }
            }
            Ok(Message::Close(_)) => {
                info!("Audio stream closed");
                break;
            }
            Err(e) => {
                error!("Audio stream error: {}", e);
                break;
            }
            _ => {}
        }
    }
}

/// Handle an outgoing WebSocket for streaming video to subscribed clients.
///
/// Subscribes to the internal video broadcast channel and forwards frames to the subscriber.
pub async fn handle_video_output(
    socket: WebSocket,
    video_tx: broadcast::Sender<Vec<u8>>,
) {
    let (mut sink, mut _stream) = socket.split();
    let mut rx = video_tx.subscribe();
    info!("Video output stream connected");

    loop {
        tokio::select! {
            frame = rx.recv() => {
                match frame {
                    Ok(data) => {
                        if let Err(e) = sink.send(Message::Binary(data.into())).await {
                            error!("Failed to send video frame: {}", e);
                            break;
                        }
                    }
                    Err(broadcast::error::RecvError::Lagged(n)) => {
                        warn!("Video output lagged by {} frames", n);
                    }
                    Err(_) => break,
                }
            }
        }
    }
}

/// Handle an outgoing WebSocket for streaming audio to subscribed clients.
///
/// Subscribes to the internal audio broadcast channel and forwards frames to the subscriber.
pub async fn handle_audio_output(
    socket: WebSocket,
    audio_tx: broadcast::Sender<Vec<u8>>,
) {
    let (mut sink, mut _stream) = socket.split();
    let mut rx = audio_tx.subscribe();
    info!("Audio output stream connected");

    loop {
        tokio::select! {
            frame = rx.recv() => {
                match frame {
                    Ok(data) => {
                        if let Err(e) = sink.send(Message::Binary(data.into())).await {
                            error!("Failed to send audio frame: {}", e);
                            break;
                        }
                    }
                    Err(broadcast::error::RecvError::Lagged(n)) => {
                        warn!("Audio output lagged by {} frames", n);
                    }
                    Err(_) => break,
                }
            }
        }
    }
}
