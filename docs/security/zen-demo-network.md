# zen_demo network boundary — issue 199

Investigation and changes: 2026-10-30. Host: macOS 27.0 (26A428), Flutter 3.47.7,
Dart 3.13.5, engine `deb287481e3ce9468f3434937ced4240a70539ca`.

## Findings and attribution

The reported command was `task run:demo:native`. Its device picker previously ran
`flutter devices --machine` without a connection filter. The installed Flutter
`DevicesCommandOutputWithExtendedWirelessDeviceDiscovery` searches for wireless
devices on macOS by default; `--device-connection=attached` avoids that path.
This is a confirmed discovery path in the launch tools, not proof that it caused
the permission dialog attributed to the app.

On iOS, Flutter's `FlutterDartVMServicePublisher` invokes `DNSServiceRegister` for
`_dartVmService._tcp` in `local.`: all interfaces on a physical device, loopback on
the simulator. The payload advertises the debugger endpoint, including its auth
code; it is not the app's backend traffic. This publisher is in the iOS engine,
not the macOS engine. It must not be used to explain the macOS report without
runtime evidence. The launcher passes `--no-publish-port`; the shared Xcode Debug,
Profile and Test launch actions pass the corresponding
`--disable-vm-service-publication` engine switch for launches outside the task
launcher. iOS build configuration also sets `DISABLE_PORT_PUBLICATION=YES` to
prevent Flutter's build-time insertion of Bonjour keys.

An initial macOS Debug launch was stopped in LLDB before socket calls. Observed:
`dart::bin::ServerSocket::CreateBindListen` → `__bind`, address `127.0.0.1`, ephemeral
port 54668, inside `zen_demo_client` (PID 54027). A socket snapshot showed only
that loopback VM-service listener. No outgoing device connection or Bonjour
registration was observed in that startup. Available historical app logs did not
identify the original trigger. XPC connections to macOS services are IPC, not
evidence of LAN traffic. This was not a complete packet capture.

**The precise cause of the original macOS dialog remains unproven.** Absence of a
dialog in later runs, especially with permission already denied, cannot prove
that the triggering operation never happened.

## Enforced changes

- Explicit desktop targets bypass enumeration; other targets list built-in/USB
  devices only. Both device selection and `flutter run` disable wireless discovery.
  CLI analytics is suppressed for these launch-tool invocations without changing
  the user's global Flutter settings.
- Before constructing Flutter bindings or application clients, native startup
  installs an HTTP connection policy for the compile-time `ZEN_API_URL` origin.
  HTTP and WebSocket upgrades must match its scheme, host and port, including on
  redirects. Proxies are disabled. Names needing local discovery are rejected
  before resolution; DNS names are resolved as absolute names without a search suffix.
- Every DNS answer must be public unicast. Private, shared, link-local, multicast,
  unspecified and reserved ranges are refused, including IPv4-mapped IPv6 and
  translation ranges. Loopback is allowed only when explicitly configured as
  `localhost` or a loopback literal, never from a public hostname's DNS answer.
  Connections use the checked numeric address without another lookup; TLS retains
  the original hostname for SNI and certificate validation. Socket failures remain
  visible. A private LAN backend is deliberately refused; same-machine Android
  development can use USB/emulator `adb reverse` with device loopback.
- Profile has its own entitlements without JIT. Release disables Xcode's injection
  of base entitlements: the inspected original Release product unexpectedly had
  `com.apple.security.get-task-allow`; the corrected product must not have it.
- `verify:demo-network`, composed into `verify:boundaries`, checks declarations,
  entitlement sets, launch flags, raw-network API additions and reviewed Apple
  plugin versions. The artifact check also reads generated plugin inventory,
  signed entitlements and embedded privacy manifests. CI builds and checks all
  three macOS modes. Missing required files or failed inspection fail the gate.

## Retained capabilities and dependency review

| Capability | Purpose and evidence |
| --- | --- |
| macOS app sandbox, all modes | OS isolation; checked in signed products. |
| macOS `network.client`, all modes | Configured jZen backend; removing it breaks sandboxed outbound requests. It is a broad OS capability, narrowed for the current Dart HTTP paths by the policy above. |
| macOS `network.server`, Debug/Profile | The local VM service for debugger/profiler attachment, observed bound to `127.0.0.1`; no application server is started. Absent in Release. |
| macOS `allow-jit`, Debug only | Flutter's JIT execution/hot reload. AOT Profile and Release have no such need. |
| `get-task-allow`, development Debug/Profile products | Xcode debugger attachment. Forbidden in Release. |
| `app_links` 7.2.1 | Receives OS-delivered confirmation/recovery URLs. Reviewed macOS implementation uses Apple events and Flutter channels; no network/discovery API found. |
| `flutter_secure_storage_darwin` 0.3.2 | Refresh token in the Keychain via `SecItem*`; app options use device-only accessibility. No outbound/discovery implementation found in the reviewed Apple source. |
| `path_provider_foundation` 2.6.0 | Filesystem paths; appears in plugin metadata as `native_build=false` on the inspected toolchain. Reviewed source has no discovery/network implementation. |
| Apple custom URL scheme `zendemo` | Auth callback delivery, not LAN discovery. Neither Apple source Info.plist requests camera, microphone, location or local-network access. |
| Android INTERNET, all modes | Configured backend. The built debug APK contains no nearby Wi-Fi/Bluetooth/location permission. |
| AndroidX `DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION` | App-scoped signature permission in the merged APK, protecting internal broadcast receivers; it is not a nearby-device capability. |
| Android PROCESS_TEXT activity query | Flutter text-selection integration with installed text handlers; no network discovery capability. |

The reviewed Apple plugin privacy manifests declare no tracking domains or
collected data types. The generated macOS registrant registers app links and secure
storage only. No analytics/discovery SDK was found in the demo's runtime dependency
graph; Flutter developer-tool telemetry is a separate process/capability. Android
manifests, iOS source declarations, Windows/Linux runners and Dart transport were
inspected; this is not a runtime traffic audit on those hosts. Android currently
declared INTERNET only in debug/profile manifests. It is now declared once in main
for every mode; the redundant development manifests were removed. No nearby-device
permission was added. Runtime behavior on Android still needs device verification.

## Verification and remaining work

Completed on this host:

- Client tests: 36 passed, including real loopback HTTP/cookies/WebSocket and
  HTTPS/WSS. Untrusted certificates and wrong hostnames are refused. Redirects to a
  second live listener never arrive there. DNS tests inject disallowed answers;
  they do not contact LAN devices. TLS fixtures are public test-only assets; no
  system trust configuration was changed.
- Script suite: 230 tests passed. Source boundary, widget-file, documentation and
  static-analysis checks passed. Initial security scans of the demo and scripts
  reported zero findings; rescanning the final edits required Snyk authentication,
  which could not be completed during this run. The final revision is not claimed
  to have a completed security rescan.
- Final Debug, Profile and Release macOS products built and passed entitlement/
  plist/privacy checks, including removal of Profile's unnecessary JIT right.
- iOS Simulator and Android debug builds passed. The built iOS plist contains no
  Bonjour/local-network usage keys. Inspection of APK permissions found only
  INTERNET and AndroidX's app-scoped signature receiver permission. Linux and
  Windows compilation was explicitly skipped on this macOS host.
- System Settings showed `zen_demo_client` Local Network **off**, already set that
  way before inspection; no permission was granted or changed. Live Debug and
  Profile launches displayed the login screen and reached a server bound only to
  `127.0.0.1:8085`. The server received synthetic login and refresh requests and
  the app displayed its response. No real credentials were used. Debug socket
  snapshots showed only loopback debugger connections. Release also reached the
  loopback fixture: its startup `GET /api/v1/auth/identity` was recorded at
  13:33:29 Europe/Warsaw and received the fixture's 404 response. Its socket snapshot
  had no listener. After the Mac was unlocked, the interactive Release login test
  also passed: synthetic credentials reached the loopback fixture and the UI
  displayed its expected unauthorized response. The server recorded login and
  refresh requests; no real account was used or authenticated. System Settings
  was inspected again and still showed `zen_demo_client` Local Network **off**.
  No permission prompt appeared in this denied-state check. The Release app and
  temporary fixture server were stopped afterwards.

Reproduce source/tests/artifact checks from the repository root:

```sh
task verify:boundaries
task test:scripts
task test:apps:client
task verify:demo-network:macos
ZEN_TARGET=macos ZEN_MODE=release ZEN_API_URL=http://127.0.0.1:8085 task run:demo:native
```

Remaining acceptance work: reproduce the original macOS prompt with the exact
trigger and a clean permission state, then compare all modes. Apple documents no
supported macOS reset to the undetermined Local Network state; do not delete system
privacy databases or assume `tccutil` resets this privilege. Use a clean test Mac/VM
with a stable signed identity. The existing denied state is a denial test, not a
clean-state test. No clean VM or physical iOS/Android device was available in this run.

Clean-state follow-up: a temporary standard account (UID 502) and verified copies
of the three products with a loopback test helper were prepared with the owner's
authorization. The owner entered the account's GUI session; the app test did not
run and no report was produced. Computer-use control remained attached to the
original account and became unavailable at the lock screen. Access to the other
GUI launchd domain was denied even outside the command sandbox; administrator
access requires a password. No clean-state result is inferred from this attempt.

The owner subsequently deleted the account and performed administrator cleanup.
Final inspection confirmed that its directory-service record and home directory
`/Users/jzen_net_audit` no longer exist; no `jzen-network-audit*` test package or
report remains in `/Users/Shared`. One OS helper, `secinitd` (PID 10693), still runs
under the former UID 502 after termination was requested. Thus filesystem/account
cleanup is verified, but termination of every associated process is not. A normal
system restart will end that remaining process; none of the test apps or helper
servers remains running under UID 502.

`HttpOverrides` is not a process firewall: native plugin/engine sockets, raw Dart
sockets, other isolates and browser-owned networking are outside its interception.
The static/API/plugin gates are review tripwires, not a proof about arbitrary native
code. Public IPs routed onto a local interface cannot be classified by address range
alone. macOS entitlements cannot express an exact backend-host allowlist. The shared
Xcode scheme supplies the engine's publication-disable argument for Debug, Profile
and Test launches; the build setting alone only prevents plist injection. This
argument path has not been exercised on a physical iOS device. Launching an installed
Debug/Profile app outside Flutter or Xcode does not provide that argument, so the
engine may still attempt Bonjour publication there. This limitation and the
unavailable physical-device check prevent claiming all of issue 199's acceptance
criteria are complete.

## Transparency assessment

The launcher names the configured backend before starting the app and explains
that debugging uses a same-machine connection with Bonjour advertising disabled.
The backend receives the API data needed for requested operations (for example
login email/password, session tokens, profile fields and chosen language). No
device inventory has a product purpose, so none is requested. No permission prompt
or approval workaround was added; refusal of unnecessary LAN access does not gate
backend requests. Apple controls the system prompt wording and does not show an
exact socket recipient there.

An OS permission is not by itself a GDPR legal basis or consent for every use of
data. The design addresses purpose limitation, minimisation and transparency;
each deployment's controller still needs an appropriate Article 6 basis and an
Article 13 notice covering its actual recipients, retention and transfers. The
dialog alone establishes neither personal-data collection nor a legal violation.

Primary references:
[Apple local-network privacy](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy),
[Flutter iOS VM publisher](https://github.com/flutter/flutter/blob/master/engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterDartVMServicePublisher.mm),
[Flutter device enumeration](https://github.com/flutter/flutter/blob/master/packages/flutter_tools/lib/src/commands/devices.dart),
[IANA IPv4 special-purpose registry](https://www.iana.org/assignments/iana-ipv4-special-registry),
[IANA IPv6 special-purpose registry](https://www.iana.org/assignments/iana-ipv6-special-registry),
[GDPR Articles 5, 6 and 13](https://eur-lex.europa.eu/eli/reg/2016/679/oj/eng).
