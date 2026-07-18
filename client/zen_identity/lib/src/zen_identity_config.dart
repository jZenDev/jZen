/// Compile-time configuration for zen_identity.
///
/// Client config stays compile-time (docs/architecture/STANDARDS.md, TA-7): a
/// `String.fromEnvironment` constant so the toolchain can tree-shake per build. Override with
/// `--define=ZEN_API_URL=https://api.example.com`. Renamed from DartZen's `DZ_*` convention.
const String zenApiUrl = String.fromEnvironment(
  'ZEN_API_URL',
  defaultValue: 'http://localhost:8080',
);
