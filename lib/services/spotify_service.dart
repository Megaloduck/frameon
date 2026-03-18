import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:app_links/app_links.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:url_launcher/url_launcher.dart';

// ── Spotify app credentials ───────────────────────────────────────────────
// Create a free Spotify Developer app at https://developer.spotify.com
// Set redirect URI to: frameon://spotify-callback
// IMPORTANT: Replace these with your own credentials.

const _kClientId = 'YOUR_SPOTIFY_CLIENT_ID';
const _kRedirectUri = 'frameon://spotify-callback';
const _kScopes =
    'user-read-playback-state user-modify-playback-state user-read-currently-playing';

// ── Models ────────────────────────────────────────────────────────────────

class SpotifyTrack {
  final String id;
  final String trackName;
  final String artistName;
  final String albumName;
  final String? albumArtUrl;
  final bool isPlaying;
  final int progressMs;
  final int durationMs;

  const SpotifyTrack({
    required this.id,
    required this.trackName,
    required this.artistName,
    required this.albumName,
    this.albumArtUrl,
    required this.isPlaying,
    required this.progressMs,
    required this.durationMs,
  });

  double get progressFraction =>
      durationMs > 0 ? (progressMs / durationMs).clamp(0.0, 1.0) : 0;

  String get progressLabel {
    String fmt(int ms) {
      final s = ms ~/ 1000;
      return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
    }
    return '${fmt(progressMs)} / ${fmt(durationMs)}';
  }

  factory SpotifyTrack.fromJson(Map<String, dynamic> json) {
    final item = json['item'] as Map<String, dynamic>? ?? {};
    final album = item['album'] as Map<String, dynamic>? ?? {};
    final images = album['images'] as List? ?? [];
    // Pick the smallest image >= 64px to minimize bandwidth
    final artUrl = images.isNotEmpty
        ? (images.lastWhere(
            (i) => (i['width'] as int? ?? 0) >= 64,
            orElse: () => images.last,
          )['url'] as String?)
        : null;

    final artists = (item['artists'] as List? ?? [])
        .map((a) => a['name'] as String? ?? '')
        .where((n) => n.isNotEmpty)
        .join(', ');

    return SpotifyTrack(
      id: item['id'] as String? ?? '',
      trackName: item['name'] as String? ?? 'Unknown',
      artistName: artists.isNotEmpty ? artists : 'Unknown Artist',
      albumName: album['name'] as String? ?? '',
      albumArtUrl: artUrl,
      isPlaying: json['is_playing'] as bool? ?? false,
      progressMs: json['progress_ms'] as int? ?? 0,
      durationMs: item['duration_ms'] as int? ?? 0,
    );
  }
}

enum SpotifyAuthState { loggedOut, authorizing, loggedIn, error }

class SpotifyServiceState {
  final SpotifyAuthState auth;
  final SpotifyTrack? track;
  final Uint8List? albumArtProcessed; // 64×32 RGB565 pixels, ready for ESP32
  final String? errorMessage;

  const SpotifyServiceState({
    this.auth = SpotifyAuthState.loggedOut,
    this.track,
    this.albumArtProcessed,
    this.errorMessage,
  });

  SpotifyServiceState copyWith({
    SpotifyAuthState? auth,
    SpotifyTrack? track,
    Uint8List? albumArtProcessed,
    String? errorMessage,
  }) =>
      SpotifyServiceState(
        auth: auth ?? this.auth,
        track: track ?? this.track,
        albumArtProcessed: albumArtProcessed ?? this.albumArtProcessed,
        errorMessage: errorMessage,
      );
}

// ── Service ───────────────────────────────────────────────────────────────

class SpotifyService extends Notifier<SpotifyServiceState> {
  static const _storage = FlutterSecureStorage();
  static const _accessKey = 'spotify_access_token';
  static const _refreshKey = 'spotify_refresh_token';
  static const _expiryKey = 'spotify_token_expiry';

  String? _codeVerifier;
  Timer? _pollTimer;
  Timer? _refreshTimer;
  StreamSubscription? _deepLinkSub;

  @override
  SpotifyServiceState build() {
    ref.onDispose(() {
      _pollTimer?.cancel();
      _refreshTimer?.cancel();
      _deepLinkSub?.cancel();
    });
    _tryLoadTokens();
    return const SpotifyServiceState();
  }

  // ── Auth ──────────────────────────────────────────────────────────────

  Future<void> login() async {
    state = state.copyWith(auth: SpotifyAuthState.authorizing);

    // PKCE code verifier + challenge
    _codeVerifier = _generateCodeVerifier();
    final challenge = _generateCodeChallenge(_codeVerifier!);

    final authUrl = Uri.https('accounts.spotify.com', '/authorize', {
      'client_id': _kClientId,
      'response_type': 'code',
      'redirect_uri': _kRedirectUri,
      'scope': _kScopes,
      'code_challenge_method': 'S256',
      'code_challenge': challenge,
    });

    if (!await launchUrl(authUrl, mode: LaunchMode.externalApplication)) {
      state = state.copyWith(
        auth: SpotifyAuthState.error,
        errorMessage: 'Could not open browser for Spotify login',
      );
      return;
    }

    // Listen for the callback deep link
    _deepLinkSub?.cancel();
    _deepLinkSub = AppLinks().uriLinkStream.listen((uri) async {
      if (uri.scheme == 'frameon' && uri.host == 'spotify-callback') {
        final code = uri.queryParameters['code'];
        if (code != null) await _exchangeCode(code);
        _deepLinkSub?.cancel();
      }
    });
  }

  Future<void> logout() async {
    _pollTimer?.cancel();
    _refreshTimer?.cancel();
    await _storage.delete(key: _accessKey);
    await _storage.delete(key: _refreshKey);
    await _storage.delete(key: _expiryKey);
    state = const SpotifyServiceState();
  }

  // ── Playback controls ─────────────────────────────────────────────────

  Future<void> play() => _playerCommand('play');
  Future<void> pause() => _playerCommand('pause');
  Future<void> next() => _playerCommand('next');
  Future<void> previous() => _playerCommand('previous');

  Future<void> _playerCommand(String cmd) async {
    final token = await _getValidToken();
    if (token == null) return;

    final (method, path) = switch (cmd) {
      'play' => ('PUT', '/v1/me/player/play'),
      'pause' => ('PUT', '/v1/me/player/pause'),
      'next' => ('POST', '/v1/me/player/next'),
      'previous' => ('POST', '/v1/me/player/previous'),
      _ => ('PUT', '/v1/me/player/play'),
    };

    try {
      await http.Request(method, Uri.https('api.spotify.com', path))
        ..headers['Authorization'] = 'Bearer $token'
        ..send();
      // Optimistic update — refresh in 500ms
      await Future.delayed(const Duration(milliseconds: 500));
      await refreshNow();
    } catch (e) {
      debugPrint('Spotify command $cmd error: $e');
    }
  }

  // ── Polling ───────────────────────────────────────────────────────────

  void startPolling({int intervalSeconds = 5}) {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
      Duration(seconds: intervalSeconds),
      (_) => refreshNow(),
    );
    refreshNow();
  }

  void stopPolling() => _pollTimer?.cancel();

  Future<void> refreshNow() async {
    final token = await _getValidToken();
    if (token == null) return;

    try {
      final res = await http.get(
        Uri.https('api.spotify.com', '/v1/me/player/currently-playing'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (res.statusCode == 204 || res.body.isEmpty) {
        // Nothing playing
        state = state.copyWith(track: null);
        return;
      }

      if (res.statusCode == 200) {
        final json = jsonDecode(res.body) as Map<String, dynamic>;
        final track = SpotifyTrack.fromJson(json);
        final artChanged = track.albumArtUrl != state.track?.albumArtUrl;

        state = state.copyWith(track: track);

        if (artChanged && track.albumArtUrl != null) {
          _fetchAndProcessArt(track.albumArtUrl!);
        }
      }
    } catch (e) {
      debugPrint('Spotify poll error: $e');
    }
  }

  // ── Album art processing ──────────────────────────────────────────────

  Future<void> _fetchAndProcessArt(String url) async {
    try {
      final res = await http.get(Uri.parse(url));
      if (res.statusCode != 200) return;

      // Decode and resize to 64×32 (half panel width × full panel height)
      // This runs in an isolate to avoid jank
      final processed = await compute(_processAlbumArt, res.bodyBytes);
      state = state.copyWith(albumArtProcessed: processed);
    } catch (e) {
      debugPrint('Album art fetch error: $e');
    }
  }

  // ── Token management ──────────────────────────────────────────────────

  Future<void> _exchangeCode(String code) async {
    try {
      final res = await http.post(
        Uri.https('accounts.spotify.com', '/api/token'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'grant_type': 'authorization_code',
          'code': code,
          'redirect_uri': _kRedirectUri,
          'client_id': _kClientId,
          'code_verifier': _codeVerifier!,
        },
      );

      if (res.statusCode == 200) {
        await _saveTokens(jsonDecode(res.body) as Map<String, dynamic>);
        state = state.copyWith(auth: SpotifyAuthState.loggedIn);
        startPolling();
      } else {
        state = state.copyWith(
          auth: SpotifyAuthState.error,
          errorMessage: 'Auth failed (${res.statusCode})',
        );
      }
    } catch (e) {
      state = state.copyWith(
        auth: SpotifyAuthState.error,
        errorMessage: 'Auth error: $e',
      );
    }
  }

  Future<void> _tryLoadTokens() async {
    final access = await _storage.read(key: _accessKey);
    final expiry = await _storage.read(key: _expiryKey);
    if (access == null) return;

    final expiryTime = expiry != null
        ? DateTime.fromMillisecondsSinceEpoch(int.tryParse(expiry) ?? 0)
        : DateTime.now().subtract(const Duration(hours: 1));

    if (DateTime.now().isBefore(expiryTime)) {
      state = state.copyWith(auth: SpotifyAuthState.loggedIn);
      startPolling();
    } else {
      await _refreshTokens();
    }
  }

  Future<void> _refreshTokens() async {
    final refresh = await _storage.read(key: _refreshKey);
    if (refresh == null) return;

    try {
      final res = await http.post(
        Uri.https('accounts.spotify.com', '/api/token'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'grant_type': 'refresh_token',
          'refresh_token': refresh,
          'client_id': _kClientId,
        },
      );

      if (res.statusCode == 200) {
        await _saveTokens(jsonDecode(res.body) as Map<String, dynamic>);
        state = state.copyWith(auth: SpotifyAuthState.loggedIn);
        startPolling();
      } else {
        state = state.copyWith(auth: SpotifyAuthState.loggedOut);
      }
    } catch (_) {
      state = state.copyWith(auth: SpotifyAuthState.loggedOut);
    }
  }

  Future<void> _saveTokens(Map<String, dynamic> json) async {
    final access = json['access_token'] as String;
    final refresh = json['refresh_token'] as String?;
    final expiresIn = json['expires_in'] as int? ?? 3600;
    final expiry = DateTime.now()
        .add(Duration(seconds: expiresIn - 60))
        .millisecondsSinceEpoch;

    await _storage.write(key: _accessKey, value: access);
    if (refresh != null) {
      await _storage.write(key: _refreshKey, value: refresh);
    }
    await _storage.write(key: _expiryKey, value: expiry.toString());

    // Schedule auto-refresh
    _refreshTimer?.cancel();
    _refreshTimer = Timer(
      Duration(seconds: expiresIn - 120),
      _refreshTokens,
    );
  }

  Future<String?> _getValidToken() async {
    final expiry = await _storage.read(key: _expiryKey);
    final expiryTime = expiry != null
        ? DateTime.fromMillisecondsSinceEpoch(int.tryParse(expiry) ?? 0)
        : null;

    if (expiryTime != null && DateTime.now().isAfter(expiryTime)) {
      await _refreshTokens();
    }

    return _storage.read(key: _accessKey);
  }

  // ── PKCE helpers ──────────────────────────────────────────────────────

  String _generateCodeVerifier() {
    final rng = Random.secure();
    final bytes = List.generate(32, (_) => rng.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  String _generateCodeChallenge(String verifier) {
    final bytes = utf8.encode(verifier);
    final digest = sha256.convert(bytes);
    return base64Url.encode(digest.bytes).replaceAll('=', '');
  }
}

final spotifyServiceProvider =
    NotifierProvider<SpotifyService, SpotifyServiceState>(SpotifyService.new);

// ── Image processing (runs in isolate) ────────────────────────────────────

Uint8List _processAlbumArt(Uint8List raw) {
  var image = img.decodeImage(raw);
  if (image == null) return Uint8List(0);

  // Crop to square from center
  final size = min(image.width, image.height);
  final x = (image.width - size) ~/ 2;
  final y = (image.height - size) ~/ 2;
  image = img.copyCrop(image, x: x, y: y, width: size, height: size);

  // Resize to 64×32 (left half of the 32×64 panel for album art)
  image = img.copyResize(image, width: 64, height: 32,
      interpolation: img.Interpolation.average);

  // Convert to JPEG bytes (ESP32 receives as base64 JPEG)
  return Uint8List.fromList(img.encodeJpg(image, quality: 75));
}
