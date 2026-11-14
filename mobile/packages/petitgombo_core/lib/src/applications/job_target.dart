import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'applications_controller.dart';
import 'booking_controller.dart';
import 'review_models.dart';

/// Which job a shared screen (report, review) works on, and from which side: the householder
/// names it by its offer, the jobber by its booking.
class JobTarget {
  const JobTarget.householder(this.id) : householder = true;
  const JobTarget.jobber(this.id) : householder = false;

  final String id;
  final bool householder;

  String? error(WidgetRef ref) => householder
      ? ref.watch(bookingControllerProvider(id)).error
      : ref.watch(applicationsControllerProvider).error;

  bool sending(WidgetRef ref) => householder
      ? ref.watch(bookingControllerProvider(id)).sending
      : ref.watch(applicationsControllerProvider).sending;

  ReviewState? review(WidgetRef ref) => householder
      ? ref.watch(bookingControllerProvider(id)).review
      : ref.watch(applicationsControllerProvider).reviews[id];

  void clearError(WidgetRef ref) => householder
      ? ref.read(bookingControllerProvider(id).notifier).clearError()
      : ref.read(applicationsControllerProvider.notifier).clearError();

  Future<void> loadReview(WidgetRef ref) => householder
      ? ref.read(bookingControllerProvider(id).notifier).loadReview()
      : ref.read(applicationsControllerProvider.notifier).loadReview(id);

  Future<bool> report(WidgetRef ref, String text, {required bool dispute}) => householder
      ? ref.read(bookingControllerProvider(id).notifier).report(text, dispute: dispute)
      : ref.read(applicationsControllerProvider.notifier).report(id, text, dispute: dispute);

  Future<bool> submitReview(WidgetRef ref, int stars, String comment) => householder
      ? ref.read(bookingControllerProvider(id).notifier).submitReview(stars, comment)
      : ref.read(applicationsControllerProvider.notifier).submitReview(id, stars, comment);
}
