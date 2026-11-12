import 'capture.dart';
import 'verification_models.dart';

/// Every sentence of the verification screens. French only; the householder is addressed as "vous".
abstract final class VerificationCopy {
  static const title = 'Vérification de votre compte';
  static const intro = 'Trois étapes pour publier vos offres.';
  static const verified = 'Compte vérifié';
  static const verifiedBody = 'Vous pourrez bientôt publier vos offres.';
  static const signOut = 'Se déconnecter';

  static const identityTitle = "Pièce d'identité";
  static const addressTitle = 'Justificatif de domicile';
  static const homeTitle = 'Position du domicile';

  static const start = 'Commencer';
  static const restart = 'Recommencer';
  static const retry = 'Réessayer';
  static const inReview = 'En cours de vérification.';
  static const confirmed = 'Confirmé';
  static const expired = 'Justificatif expiré. Envoyez-en un nouveau.';
  static const refusedFallback = 'Refusé. Recommencez cette étape.';

  static String submitted(int hours) => 'Envoyé. Nous vérifions sous $hours h.';

  /// The sentence under a step's title.
  static String statusText(StepState step, int reviewHours) => switch (step.status) {
        StepStatus.notStarted => '',
        StepStatus.submitted => submitted(reviewHours),
        StepStatus.inReview => inReview,
        StepStatus.confirmed => confirmed,
        StepStatus.refused => step.reason.isEmpty ? refusedFallback : step.reason,
        StepStatus.expired => expired,
      };

  static const chooseIdentityDocument = 'Quel document allez-vous utiliser ?';
  static const chooseAddressDocument = 'Quel justificatif allez-vous utiliser ?';
  static const identityTypes = {
    'cni': "Carte nationale d'identité",
    'passport': 'Passeport',
    'carte_consulaire': 'Carte consulaire',
    'permis': 'Permis de conduire',
  };
  static const addressTypes = {
    'facture_eau': "Facture d'eau",
    'facture_electricite': "Facture d'électricité",
    'certificat_residence': 'Certificat de résidence',
  };

  static const captureFront = 'Recto du document';
  static const captureBack = 'Verso du document';
  static const captureSelfie = 'Votre visage';
  static const captureAddress = 'Photo du justificatif';
  static const takePhoto = 'Prendre la photo';
  static const retake = 'Reprendre';
  static const usePhoto = 'Utiliser cette photo';
  static const photoHint = 'Le document entier doit être lisible, sans reflet.';
  static const selfieHint = 'Regardez l\'appareil, visage dégagé.';
  static const summaryTitle = 'Vérifiez vos photos';
  static const send = 'Envoyer';

  static String captureTitle(PhotoKind kind) => switch (kind) {
        PhotoKind.idFront => captureFront,
        PhotoKind.idBack => captureBack,
        PhotoKind.selfie => captureSelfie,
        PhotoKind.addressProof => captureAddress,
      };

  static const addressNote = 'Le document doit être à votre nom et dater de moins de 3 mois.';
  static const addressFormTitle = 'Où se trouve votre domicile ?';
  static const commune = 'Commune';
  static const quartier = 'Quartier';
  static const communeRequired = 'Choisissez la commune.';
  static const quartierRequired = 'Indiquez le quartier.';

  static const homeIntro = 'Faites cette étape chez vous.';
  static const homeBody =
      'Nous enregistrons la position de votre domicile une seule fois. Elle ne sera jamais montrée aux mini-jobbers avant une réservation confirmée.';
  static const recordPosition = 'Enregistrer ma position';
  static const positionRecorded = 'Position enregistrée.';

  static const cameraPermission = "Autorisez l'appareil photo pour continuer.";
  static const locationPermission = 'Autorisez la localisation pour continuer.';
  static const openSettings = 'Ouvrir les réglages';
  static const positionUnavailable = 'Position indisponible. Activez la localisation et réessayez.';
  static const cameraUnavailable = "L'appareil photo est indisponible. Réessayez.";

  static const offline = 'Pas de connexion. Réessayez.';
  static const offlinePhotosKept = 'Pas de connexion. Vos photos sont gardées. Réessayez.';
  static const sessionExpired = "Votre session a expiré. Fermez puis rouvrez l'application.";
  static const genericError = 'Une erreur est survenue. Réessayez.';

  static String positionFailure(CaptureFailure failure) => switch (failure) {
        CaptureFailure.permissionDenied ||
        CaptureFailure.permissionDeniedForever =>
          locationPermission,
        CaptureFailure.unavailable => positionUnavailable,
      };

  static String cameraFailure(CaptureFailure failure) => switch (failure) {
        CaptureFailure.permissionDenied ||
        CaptureFailure.permissionDeniedForever =>
          cameraPermission,
        CaptureFailure.unavailable => cameraUnavailable,
      };
}
