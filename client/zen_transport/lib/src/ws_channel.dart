// The compile-time platform seam for opening a WebSocket, structured exactly like
// zen_codec_selector.dart and http/session_client.dart (docs/architecture/STANDARDS.md): a
// default library importing the stub, with `dart.library.io` / `dart.library.js_interop` swapping
// in the native or web implementation so the toolchain tree-shakes the wrong platform's code out
// of each bundle.
//
// The web branch keys on `dart.library.js_interop`, not `dart.library.html`: the latter is defined
// only by dart2js, so under dart2wasm it would miss and fall through to the stub. `js_interop` is
// defined by every web compiler and by none of the native ones.
//
// What the seam exists for: jZen's socket endpoint requires an authenticated handshake, and only
// one of the two platforms can attach the session itself. A browser sends its cookies on a
// same-origin upgrade automatically and accepts no custom headers; a `dart:io` WebSocket shares
// nothing with the cookie jar and must be handed the header explicitly. One runtime API cannot
// express both, which is what makes this a compile-time choice rather than an `if`.
export 'ws_channel_stub.dart'
    if (dart.library.js_interop) 'ws_channel_web.dart'
    if (dart.library.io) 'ws_channel_io.dart'
    show connectChannel;
