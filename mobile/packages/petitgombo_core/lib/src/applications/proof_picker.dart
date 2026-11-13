import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../verification/capture.dart';

/// Picks a screenshot of the mobile-money receipt from the phone's gallery. The app provides the
/// implementation (it needs a platform plugin); the core only knows this interface.
abstract class ProofPicker {
  /// Null when the person closes the picker without choosing.
  Future<CapturedPhoto?> pick();
}

final proofPickerProvider = Provider<ProofPicker>(
  (ref) => throw UnimplementedError('The app must provide a ProofPicker'),
);
