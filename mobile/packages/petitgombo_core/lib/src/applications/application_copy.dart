import '../offers/offer_format.dart';
import 'application_models.dart';

/// French messages for applications. The jobber side says "tu", the householder side "vous".
abstract final class ApplicationCopy {
  // Jobber
  static const apply = 'Postuler';
  static const applyTitle = 'Postuler à cette offre';
  static const applyBody =
      'Écris un mot au ménage si tu veux (facultatif). Pas de numéro ni de contact.';
  static const messageLabel = 'Ton message (facultatif)';
  static const send = 'Envoyer ma candidature';
  static const sent = 'Candidature envoyée';
  static const sentBody = 'Le ménage va choisir. Tu verras la réponse dans « Mes candidatures ».';
  static const withdraw = 'Retirer ma candidature';
  static const finishVerification = 'Termine ta vérification pour postuler';
  static const myApplications = 'Mes candidatures';
  static const myApplicationsSubtitle = 'Les offres auxquelles tu as postulé.';
  static const noApplications = "Tu n'as pas encore postulé.";
  static const noApplicationsBody = 'Choisis une offre et appuie sur « Postuler ».';
  static const trustHousehold = 'Ménage vérifié';
  static const acceptedWaiting = 'Acceptée : le ménage doit encore payer.';
  static const offerGone = "L'offre n'est plus disponible.";
  static const myJobs = 'Mes jobs';

  static String trustLine(HouseholderTrust trust) {
    final jobs = trust.jobsDone == 0
        ? 'aucun job terminé'
        : '${trust.jobsDone} job${trust.jobsDone > 1 ? 's' : ''} terminé${trust.jobsDone > 1 ? 's' : ''}';
    return '$trustHousehold · $jobs';
  }

  static String applicationStatus(ApplicationStatus status, {bool offerGone = false}) {
    if (offerGone && status == ApplicationStatus.pending) return ApplicationCopy.offerGone;
    return switch (status) {
      ApplicationStatus.pending => 'En attente de réponse',
      ApplicationStatus.accepted => 'Acceptée',
      ApplicationStatus.declined => 'Pas retenue',
      ApplicationStatus.withdrawn => 'Retirée',
    };
  }

  // Householder
  static const applicantsTitle = 'Candidats';
  static const noApplicants = 'Pas encore de candidat.';
  static const noApplicantsBody = 'Les jobbers vérifiés qui postulent apparaissent ici.';
  static const accept = 'Accepter';
  static const confirm = 'Confirmer';
  static const jobberLabel = 'J1';
  static const bookedLine = 'en attente de votre paiement';

  static String applicantCount(int count) => count == 1 ? '1 candidat' : '$count candidats';

  static String acceptTitle(String name) => 'Accepter $name ?';
  static const acceptBody = 'Les autres candidats seront refusés.';

  static String jobsDone(int count) => count == 0
      ? 'Aucun job terminé'
      : '$count job${count > 1 ? 's' : ''} terminé${count > 1 ? 's' : ''}';

  static String bookingLine(String name) => '$name · $bookedLine';

  // Payment and the booking, householder side
  static const unavailable = "Le paiement n'est pas disponible pour le moment.";
  static const myBooking = 'Ma réservation';
  static const pay = 'Payer';
  static const payAgain = 'Envoyer une nouvelle preuve';
  static const payTitle = 'Payer la réservation';
  static const payBody =
      'Envoyez le montant à l’un des numéros ci-dessous depuis votre application de paiement, puis revenez ici envoyer la preuve.';
  static const amountLabel = 'Montant à payer';
  static const methodLabel = 'Payé avec';
  static const referenceLabel = 'Référence de la transaction';
  static const referenceHint = 'Elle figure sur le reçu de votre paiement.';
  static const pickScreenshot = "Choisir la capture d'écran";
  static const changeScreenshot = 'Changer la capture';
  static const sendProof = 'Envoyer la preuve';
  static const copy = 'Copier le numéro';
  static const copied = 'Numéro copié';
  static const proofSent = 'Preuve envoyée. Nous vérifions votre paiement.';
  static const cancelBooking = 'Annuler la réservation';
  static const cancelBookingTitle = 'Annuler la réservation ?';
  static const cancelBookingBody =
      'Le jobber sera prévenu. Si vous avez déjà payé, nous vous remboursons.';
  static const keep = 'Garder';
  static const gone = "Cette réservation n'existe plus.";
  static const jobberLabel2 = 'Jobber';
  static const photoLabel = 'Photo vérifiée';
  static const imageUnreadable = 'Cette image ne peut pas être lue. Choisissez une autre capture.';

  static String bookingStatusLine(BookingDetail detail) {
    final payment = detail.payment;
    final arrived = detail.checkedInAt;
    final limit = detail.autoConfirmAt;
    return switch (detail.status) {
      'accepted' when payment != null && payment.refused => 'Paiement refusé : ${payment.reason}',
      'accepted' => 'Paiement à envoyer avant ${formatClock(detail.payDeadline)}',
      'payment_review' => 'Paiement en cours de vérification',
      'confirmed' || 'address_released' => 'Réservation confirmée',
      'checked_in' when arrived != null => 'Le jobber est arrivé à ${formatClock(arrived)}',
      'checked_in' => 'Job en cours',
      'completion_pending' when limit != null => 'Job à confirmer avant ${formatDeadline(limit)}',
      'completion_pending' => 'Job à confirmer',
      'completed' => 'Job terminé',
      'disputed' => 'Problème signalé : notre équipe vous répond',
      _ => 'Réservation en cours',
    };
  }

  /// "le 15 nov. à 11:00", for a limit that may fall on another day.
  static String formatDeadline(DateTime value) => 'le ${formatDay(value)} à ${formatClock(value)}';

  // The job and after, householder side
  static const confirmDone = "Confirmer que c'est fait";
  static const confirmDoneTitle = 'Le job est bien fait ?';
  static const confirmDoneBody =
      'Le jobber sera payé. Après votre confirmation, le paiement ne peut plus être gelé.';
  static const notYet = 'Pas encore';

  // Problems, both sides
  static const reportProblem = 'Signaler un problème';
  static const reportTitle = 'Signaler un problème';
  static const reportLabel = "Que s'est-il passé ?";
  static const reportHint = 'Entre 3 et 500 caractères.';
  static const reportDispute = "Faire geler le paiement et prévenir l'équipe";
  static const reportConcern = 'Remarque privée';
  static const reportConcernNote =
      "Une remarque privée est lue par notre équipe seulement. L'autre personne n'est pas prévenue.";
  static const reportSend = 'Envoyer';
  static const reportSent = 'Signalement envoyé. Notre équipe le lit.';

  // Reviews, both sides
  static const reviewAsk = 'Donnez votre avis';
  static const reviewAskJobber = 'Donne ton avis';
  static const reviewTitle = 'Votre avis';
  static const reviewTitleJobber = 'Ton avis';
  static const reviewStarsLabel = 'Note';
  static const reviewCommentLabel = 'Commentaire (facultatif)';
  static const reviewCommentHint = 'Pas de numéro ni de contact.';
  static const reviewWhen = "Publié quand l'autre personne aura donné le sien, ou après 7 jours.";
  static const reviewSend = "Envoyer l'avis";
  static const reviewSent = 'Avis envoyé';
  static const reviewOfJobber = "L'avis du jobber";
  static const reviewOfHousehold = "L'avis du ménage";
  static const reviewClosed = "Le délai pour donner un avis est dépassé.";

  static String starsLabel(int stars) => '$stars sur 5';

  static String ratingLabel(double rating) =>
      '${rating.toStringAsFixed(1).replaceAll('.', ',')} sur 5';

  static String bookingLineFor(String name, String status) => switch (status) {
        'payment_review' => '$name · paiement à vérifier',
        'confirmed' || 'address_released' => '$name · réservation confirmée',
        'checked_in' => '$name · job en cours',
        'completion_pending' => '$name · job à confirmer',
        'completed' => '$name · job terminé',
        'disputed' => '$name · problème signalé',
        _ => '$name · $bookedLine',
      };

  // The jobber's jobs
  static const myJobsEmpty = "Tu n'as pas encore de job.";
  static const jobTitle = 'Mon job';
  static const seeAddress = "Voir l'adresse exacte";
  static const addressTitle = 'Adresse du ménage';
  static const copyPin = 'Copier la position';
  static const pinCopied = 'Position copiée';
  static const cancelParticipation = 'Annuler ma participation';
  static const cancelParticipationTitle = 'Annuler ta participation ?';
  static const cancelParticipationBody = 'Le ménage sera remboursé et prévenu.';
  static const waitingPayment = 'En attente du paiement du ménage';
  static const paymentChecking = 'Le ménage a payé : nous vérifions';

  static const arrived = 'Je suis arrivé(e)';
  static const finished = "J'ai terminé";
  static const finishedTitle = 'Tu as terminé le job ?';
  static const finishedBody =
      'Le ménage va confirmer. Sans réponse de sa part, le job est validé tout seul.';
  static const arrivedWithoutPosition =
      "Arrivée enregistrée, sans ta position : ton téléphone ne l'a pas donnée.";
  static const payoutDue = 'Paiement en préparation';
  static const payoutPaid = 'Paiement envoyé';
  static const jobRunning = 'Job en cours';
  static const jobDisputed = 'Problème signalé : notre équipe regarde';

  static String confirmWait(DateTime? limit) => limit == null
      ? 'En attente de la confirmation du ménage'
      : "Le ménage a jusqu'au ${formatDay(limit)} à ${formatClock(limit)} pour confirmer";

  /// Null when there is nothing to say about the pay yet.
  static String? payoutLine(JobberBooking booking) => switch (booking.payout) {
        'due' => payoutDue,
        'paid' => payoutPaid,
        _ => null,
      };

  static String jobStatus(JobberBooking booking, DateTime now) {
    if (booking.status == 'cancelled') return 'Annulé';
    if (booking.status == 'expired') return 'Expiré';
    if (booking.status == 'completed') {
      final pay = payoutLine(booking);
      return pay == null ? 'Terminé' : 'Terminé · ${pay.toLowerCase()}';
    }
    if (booking.status == 'checked_in') return jobRunning;
    if (booking.status == 'completion_pending') return confirmWait(booking.autoConfirmAt);
    if (booking.status == 'disputed') return jobDisputed;
    if (booking.payment == 'pending') return waitingPayment;
    if (booking.payment == 'review') return paymentChecking;
    if (now.isBefore(booking.addressAvailableFrom)) {
      return "Confirmé : l'adresse arrive le ${formatDay(booking.addressAvailableFrom)} à ${formatClock(booking.addressAvailableFrom)}";
    }
    return 'Adresse disponible';
  }

  /// "Je suis arrivé(e)" is offered from a little before the start until the end.
  static bool canCheckIn(JobberBooking booking, DateTime now) =>
      const {'confirmed', 'address_released'}.contains(booking.status) &&
      !now.isBefore(booking.checkinFrom) &&
      now.isBefore(booking.endsAt);

  static bool jobReportable(JobberBooking booking) =>
      const {'checked_in', 'completion_pending', 'disputed', 'completed'}.contains(booking.status);

  static bool jobCancellable(JobberBooking booking) => const {
        'accepted',
        'payment_review',
        'confirmed',
        'address_released',
      }.contains(booking.status);
}
