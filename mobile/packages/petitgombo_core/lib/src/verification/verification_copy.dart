import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/app_role.dart';
import '../app/providers.dart';
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
  static const guarantorTitle = 'Garant';

  static const start = 'Commencer';
  static const restart = 'Recommencer';
  static const retry = 'Réessayer';
  static const inReview = 'En cours de vérification.';
  static const inProgress = 'En cours.';
  static const confirmed = 'Confirmé';
  static const expired = 'Justificatif expiré. Envoyez-en un nouveau.';
  static const refusedFallback = 'Refusé. Recommencez cette étape.';

  static String submitted(int hours) => 'Envoyé. Nous vérifions sous $hours h.';

  /// The sentence under a step's title.
  static String statusText(VerificationStep step, int reviewHours) => switch (step.status) {
        StepStatus.notStarted => '',
        StepStatus.submitted => submitted(reviewHours),
        StepStatus.inReview => inReview,
        StepStatus.inProgress => inProgress,
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
        PhotoKind.guarantorBill => captureGuarantorBill,
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

  // Trusted contacts, jobber only, in "tu".
  static const contactsTitle = 'Personnes de confiance';
  static String contactsIntro(int max) =>
      'Une personne de confiance est prévenue si quelque chose ne va pas pendant une mission. '
      "Tu peux en indiquer jusqu'à $max.";
  static const addContact = 'Ajouter une personne';
  static const changeContact = 'Changer';
  static const requestNewCode = 'Demander un nouveau code';
  static const enterCode = 'Saisir le code';
  static const confirmCode = 'Confirmer';
  static const contactFormTitle = 'Qui est ta personne de confiance ?';
  static const contactNameLabel = 'Nom de la personne';
  static const contactPhoneLabel = 'Téléphone de la personne';
  static const contactNameRequired = 'Indique le nom de la personne.';
  static const contactRelationshipHint = 'Quel est son lien avec toi ?';
  static const contactRelationships = {
    'parent': 'Parent',
    'relative': 'Famille',
    'friend': 'Ami(e)',
    'other': 'Autre',
  };
  static const contactPrivacy =
      'Notre équipe envoie un message WhatsApp à cette personne, une seule fois, pour qu\'elle '
      "confirme. On n'utilise son numéro que pour ça.";
  static const contactReplaceNote =
      'Ta personne actuelle reste en place jusqu\'à ce que la nouvelle ait confirmé, puis encore '
      'quelques jours. Notre équipe la préviendra par WhatsApp.';
  static const contactCodeTitle = 'Saisis le code';
  static String contactCodeBody(int hours) =>
      'Notre équipe envoie un code par WhatsApp à cette personne, en général sous $hours h. '
      'Demande-le-lui, puis saisis-le ici.';
  static const contactCodeLabel = 'Code à 6 chiffres';
  static const contactAwaiting = "En attente d'envoi du code";
  static const contactSent = 'Code envoyé, à saisir';
  static String contactReplacedOn(DateTime date) =>
      'Remplacée le ${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}';

  // The card on Offres, jobber only.
  static const cardTitle = 'Fais vérifier ton compte';
  static const cardVerified = 'Compte vérifié';
  static String cardProgress(int done, int total) =>
      '$done ${done > 1 ? 'étapes' : 'étape'} sur $total';

  // Guarantor flow: only jobbers see it, so it is written in "tu".
  static const guarantorFlowTitle = 'Qui se porte garant pour toi ?';
  static const guarantorNameLabel = 'Nom du garant';
  static const guarantorPhoneLabel = 'Téléphone du garant';
  static const guarantorNameRequired = 'Indique le nom de ton garant.';
  static const guarantorRelationshipHint = 'Quel est son lien avec toi ?';
  static const guarantorRelationships = {
    'parent': 'Parent',
    'relative': 'Famille',
    'landlord': 'Propriétaire',
    'other': 'Autre',
  };
  static const guarantorPrivacy =
      "On appelle ton garant pour confirmer. On utilise son numéro seulement pour ça, "
      "et la facture n'est vue que par notre équipe de vérification.";
  static const chooseGuarantorDocument = 'Quel justificatif de ton garant vas-tu envoyer ?';
  static const guarantorNote =
      'Le justificatif doit dater de moins de 3 mois et être au nom de ton garant.';
  static const guarantorDocumentTypes = {
    'facture_eau': "Facture d'eau",
    'facture_electricite': "Facture d'électricité",
    'certificat_residence': 'Certificat de résidence',
    'abonnement_prepaye': 'Abonnement prépayé',
  };
  static const captureGuarantorBill = 'Photo du justificatif';
  static const guarantorSummaryTitle = 'Vérifie les informations';
  static const guarantorPhoneInvalid = 'Numéro de téléphone invalide.';
  static const contactPhoneInvalid = 'Numéro de téléphone invalide.';
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

/// The sentences that change with the person addressed: "vous" for a householder, "tu" for a jobber.
class VerificationVoice {
  const VerificationVoice({
    required this.title,
    required this.intro,
    required this.verifiedBody,
    required this.chooseIdentityDocument,
    required this.captureSelfie,
    required this.selfieHint,
    required this.summaryTitle,
    required this.identityPrivacy,
  });

  static const vous = VerificationVoice(
    title: VerificationCopy.title,
    intro: VerificationCopy.intro,
    verifiedBody: VerificationCopy.verifiedBody,
    chooseIdentityDocument: VerificationCopy.chooseIdentityDocument,
    captureSelfie: VerificationCopy.captureSelfie,
    selfieHint: VerificationCopy.selfieHint,
    summaryTitle: VerificationCopy.summaryTitle,
    identityPrivacy:
        'Vos photos sont chiffrées et vues seulement par notre équipe de vérification. '
        'Chaque consultation est enregistrée.',
  );

  static const tu = VerificationVoice(
    title: 'Vérifie ton compte',
    intro: 'Deux étapes pour pouvoir postuler.',
    verifiedBody: 'Tu pourras bientôt postuler aux offres.',
    chooseIdentityDocument: 'Quel document vas-tu utiliser ?',
    captureSelfie: 'Ton visage',
    selfieHint: "Regarde l'appareil, visage dégagé.",
    summaryTitle: 'Vérifie tes photos',
    identityPrivacy:
        'Tes photos sont chiffrées et vues seulement par notre équipe de vérification. '
        'Chaque consultation est enregistrée.',
  );

  final String title;
  final String intro;
  final String verifiedBody;
  final String chooseIdentityDocument;
  final String captureSelfie;
  final String selfieHint;
  final String summaryTitle;
  final String identityPrivacy;

  String captureTitle(PhotoKind kind) =>
      kind == PhotoKind.selfie ? captureSelfie : VerificationCopy.captureTitle(kind);
}

final verificationVoiceProvider = Provider<VerificationVoice>(
  (ref) =>
      ref.watch(appRoleProvider) == AppRole.jobber ? VerificationVoice.tu : VerificationVoice.vous,
);
