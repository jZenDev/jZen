import 'package:flutter/widgets.dart' show FormFieldValidator;
import 'package:zen_core/zen_core.dart' show EmailAddress;

import '../l10n/generated/identity_localizations.dart';

/// The validator of every e-mail field on the identity screens.
///
/// It judges the **trimmed** text, because the submit handlers send the trimmed text: a space
/// left by pasting an address on a phone must not be reported as an invalid address the form
/// would have accepted. Whitespace *inside* an address is still invalid.
FormFieldValidator<String> identityEmailValidator(IdentityLocalizations messages) {
  return (value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) {
      return messages.validationRequired;
    }
    if (EmailAddress.create(email).isFailure) {
      return messages.validationEmail;
    }
    return null;
  };
}
