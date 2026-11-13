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
}
