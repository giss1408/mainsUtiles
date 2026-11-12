import '../app/app_role.dart';

/// Screen text for enrolment. The householder app says "vous", the jobber app "tu".
class EnrolmentCopy {
  const EnrolmentCopy._({
    required this.phoneTitle,
    required this.phoneNote,
    required this.heldBody,
    required this.expiredBody,
    required this.roleLabel,
  });

  factory EnrolmentCopy.forRole(AppRole role) => switch (role) {
        AppRole.householder => const EnrolmentCopy._(
            phoneTitle: 'Votre numéro de téléphone',
            phoneNote: 'Nous vous enverrons un numéro de confirmation par WhatsApp.',
            heldBody: 'Votre demande est en cours de vérification.',
            expiredBody: 'Votre demande a expiré.',
            roleLabel: 'Particulier',
          ),
        AppRole.jobber => const EnrolmentCopy._(
            phoneTitle: 'Ton numéro de téléphone',
            phoneNote: "On t'envoie un numéro de confirmation par WhatsApp.",
            heldBody: 'Ta demande est en cours de vérification.',
            expiredBody: 'Ta demande a expiré.',
            roleLabel: 'Mini-jobber',
          ),
      };

  final String phoneTitle;
  final String phoneNote;
  final String heldBody;
  final String expiredBody;
  final String roleLabel;

  static const phonePrefix = '+225';
  static const phoneHint = '07 08 09 10 11';
  static const continueLabel = 'Continuer';
  static const pendingTitle = 'Demande reçue';
  static String pendingBody(int hours) => 'Confirmation par WhatsApp sous $hours h.';
  static const refreshLabel = 'Actualiser';
  static const codeTitle = 'Numéro de confirmation';
  static const codeNote = 'Notre équipe ne vous demandera jamais ce numéro.';
  static const validateLabel = 'Valider';
  static const refusedTitle = 'Demande refusée';
  static const lockedBody = "Trop d'essais. Faites une nouvelle demande.";
  static const startOverLabel = 'Nouvelle demande';
  static const retryLabel = 'Réessayer';
  static const welcome = 'Bienvenue';
  static const signOutLabel = 'Se déconnecter';
  static const signedOutBody = 'Vous êtes déconnecté.';
  static const signInLabel = 'Se reconnecter';
  static const loading = 'Chargement…';
}
