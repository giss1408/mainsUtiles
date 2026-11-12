import '../api/models.dart';

/// Where the user is in device enrolment.
sealed class EnrolmentState {
  const EnrolmentState();
}

class EnrolmentInitial extends EnrolmentState {
  const EnrolmentInitial();
}

class EnrolmentSubmitting extends EnrolmentState {
  const EnrolmentSubmitting();
}

class EnrolmentPending extends EnrolmentState {
  const EnrolmentPending(this.responseHours);
  final int responseHours;
}

class EnrolmentHeld extends EnrolmentState {
  const EnrolmentHeld(this.reason);
  final String? reason;
}

class EnrolmentAwaitingCode extends EnrolmentState {
  const EnrolmentAwaitingCode({this.errorMessage});
  final String? errorMessage;
}

class EnrolmentRefused extends EnrolmentState {
  const EnrolmentRefused(this.reason);
  final String? reason;
}

class EnrolmentLocked extends EnrolmentState {
  const EnrolmentLocked();
}

class EnrolmentExpired extends EnrolmentState {
  const EnrolmentExpired();
}

class EnrolmentDone extends EnrolmentState {
  const EnrolmentDone(this.me);
  final Me me;
}

/// Something went wrong; [previous] is the screen to keep showing under the message.
class EnrolmentFailure extends EnrolmentState {
  const EnrolmentFailure(this.message, {required this.previous});
  final String message;
  final EnrolmentState previous;
}
