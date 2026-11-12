import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:petitgombo_core/petitgombo_core.dart';

/// Holds a fixed state and records what the screens ask for.
class FakeEnrolmentController extends StateNotifier<EnrolmentState>
    implements EnrolmentController {
  FakeEnrolmentController(super.state);

  String? submittedPhone;
  String? submittedCode;
  int refreshes = 0;
  int startOvers = 0;

  @override
  Future<void> submitPhone(String input) async => submittedPhone = input;

  @override
  Future<void> submitCode(String code) async => submittedCode = code;

  @override
  Future<void> refresh() async => refreshes++;

  @override
  Future<void> resume() async {}

  @override
  Future<void> startOver() async => startOvers++;
}
