/// The HTTP methods [ZenClient] can issue. Using an enum keeps the verb strings in one
/// place and makes an unsupported method unrepresentable at the call site.
enum ZenHttpMethod {
  /// HTTP GET.
  get('GET'),

  /// HTTP POST.
  post('POST'),

  /// HTTP PUT.
  put('PUT'),

  /// HTTP DELETE.
  delete('DELETE');

  const ZenHttpMethod(this.value);

  /// The wire verb (e.g. `GET`).
  final String value;
}
