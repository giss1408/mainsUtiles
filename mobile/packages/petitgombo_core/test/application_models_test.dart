import 'package:flutter_test/flutter_test.dart';
import 'package:petitgombo_core/petitgombo_core.dart';

import 'support/application_fixtures.dart';
import 'support/offer_fixtures.dart';

void main() {
  test('a public offer carries the householder trust line and my application', () {
    final json = {
      ...publicOfferJson(),
      'householder': trustJson(),
      'my_application': {'id': 'a-1', 'status': 'pending'},
    };
    final offer = PublicOffer.fromJson(json);
    expect(offer.householder!.tier, 'H1');
    expect(offer.householder!.jobsDone, 3);
    expect(offer.householder!.rating, isNull);
    expect(offer.myApplication!.status, ApplicationStatus.pending);
    expect(PublicOffer.fromJson(publicOfferJson()).householder, isNull);
    expect(PublicOffer.fromJson(publicOfferJson()).myApplication, isNull);
  });

  test('a booked offer parses and my offer carries the count and the booking', () {
    expect(OfferStatus.parse('booked'), OfferStatus.booked);
    final offer = MyOffer.fromJson({
      ...myOfferJson(status: 'booked'),
      'applicants_count': 2,
      'booking': {'id': 'b-1', 'status': 'accepted', 'jobber_first_name': 'Awa'},
    });
    expect(offer.applicantsCount, 2);
    expect(offer.booking!.jobberFirstName, 'Awa');
    expect(offer.copyWithStatus(OfferStatus.closed).booking!.id, 'b-1');
    expect(MyOffer.fromJson(myOfferJson()).applicantsCount, 0);
    expect(MyOffer.fromJson(myOfferJson()).booking, isNull);
  });

  test('an unknown application status reads as pending', () {
    expect(ApplicationStatus.parse('weird'), ApplicationStatus.pending);
    expect(ApplicationStatus.parse('accepted'), ApplicationStatus.accepted);
    expect(ApplicationStatus.parse('declined'), ApplicationStatus.declined);
    expect(ApplicationStatus.parse('withdrawn'), ApplicationStatus.withdrawn);
  });

  test('a jobber application, an applicant and a booking parse', () {
    final item = JobberApplication.fromJson(applicationItemJson(
      status: 'accepted',
      booking: {'id': 'b-1', 'status': 'accepted'},
    ));
    expect(item.status, ApplicationStatus.accepted);
    expect(item.offer.categoryName, 'Ménage');
    expect(item.offer.payXof, 3500);
    expect(item.booking!.id, 'b-1');
    expect(JobberApplication.fromJson(applicationItemJson()).booking, isNull);

    final applicant = ApplicantCard.fromJson(applicantJson());
    expect((applicant.firstName, applicant.tier, applicant.jobsDone), ('Awa', 'J1', 2));
    expect(applicant.message, 'Disponible le matin.');

    final booking = BookingSummary.fromJson(acceptedJson());
    expect((booking.id, booking.jobberFirstName), ('b-1', 'Awa'));
    expect(JobberBooking.fromJson(jobberBookingJson()).quartier, 'Angré');
  });
}
