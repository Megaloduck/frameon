/// UUIDs must match exactly what's declared in the ESP32 firmware.
/// All UUIDs are 128-bit in standard string format.
library ble_uuids;

// ── Service ───────────────────────────────────────────────────────────────────

/// Primary Frameon BLE service
const String kFrameonServiceUuid = '12345678-1234-1234-1234-123456789abc';

// ── Characteristics ───────────────────────────────────────────────────────────

/// Write-only: raw RGB565 frame chunk (up to MTU-3 bytes per write)
const String kFrameDataUuid = '12345678-1234-1234-1234-123456789ab1';

/// Write-only: control commands (play/pause, clear, set mode, set brightness)
const String kControlUuid = '12345678-1234-1234-1234-123456789ab2';

/// Notify: acknowledgement / status from ESP32
const String kStatusUuid = '12345678-1234-1234-1234-123456789ab3';

/// Write-only: clock config (epoch timestamp + format flags)
const String kClockConfigUuid = '12345678-1234-1234-1234-123456789ab4';

/// Write-only: GIF frame timing metadata (frame count, durations array)
const String kGifMetaUuid = '12345678-1234-1234-1234-123456789ab5';

// ── Control command bytes ─────────────────────────────────────────────────────

/// Sent to [kControlUuid] to signal start of a new frame transfer
const int kCmdFrameBegin = 0x01;

/// Sent to [kControlUuid] after all chunks are written — commit and display
const int kCmdFrameCommit = 0x02;

/// Clear the matrix to black
const int kCmdClear = 0x03;

/// Set display mode: [0x04, modeId]
const int kCmdSetMode = 0x04;

/// Set brightness: [0x05, value 0-255]
const int kCmdSetBrightness = 0x05;

/// Abort current transfer
const int kCmdAbort = 0x06;

/// Ping — ESP32 echoes back 0x07 via [kStatusUuid]
const int kCmdPing = 0x07;

// ── Display modes ─────────────────────────────────────────────────────────────

const int kModeStill    = 0x00;
const int kModeGif      = 0x01;
const int kModeClock    = 0x02;
const int kModeSpotify  = 0x03;
const int kModePixelArt = 0x04;

// ── Status bytes (received from ESP32 via notify) ─────────────────────────────

const int kStatusOk      = 0x00;
const int kStatusError   = 0x01;
const int kStatusBusy    = 0x02;
const int kStatusReady   = 0x03;

// ── Protocol constants ────────────────────────────────────────────────────────

/// Default chunk size (bytes) if MTU negotiation fails.
/// BLE MTU max payload = negotiated MTU - 3 bytes ATT overhead.
const int kDefaultChunkSize = 244; // assumes 247 MTU

/// Full frame size in bytes: 64 * 32 * 2 bytes (RGB565, big-endian)
const int kFrameSizeBytes = 64 * 32 * 2; // 4096

/// Delay between chunks to avoid overwhelming the ESP32 write buffer.
const Duration kChunkDelay = Duration(milliseconds: 5);

/// How long to wait for an ack before timing out.
const Duration kAckTimeout = Duration(seconds: 5);

/// Device name advertised by ESP32
const String kFrameonDeviceName = 'Frameon';