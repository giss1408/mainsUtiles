import 'offer_format.dart';
import 'offer_models.dart';

/// French messages for the offer screens (householder "vous").
abstract final class OfferCopy {
  static const offline = 'Pas de connexion. Réessayez.';
  static const sessionExpired = 'Votre session a expiré. Ouvrez l’application à nouveau.';
  static const genericError = 'Une erreur est survenue. Réessayez.';
  static const loadFailed = 'Les offres n’ont pas pu être chargées.';
  static const retry = 'Réessayer';
  static const cancel = 'Annuler';
  static const signOut = 'Se déconnecter';

  // My offers
  static const myOffersTitle = 'Mes offres';
  static const verifiedRow = 'Compte vérifié';
  static const createOffer = 'Créer une offre';
  static const myOffersSubtitle = 'Publiez une offre et suivez son état ici.';
  static const emptyMine = "Vous n'avez pas encore d'offre.";
  static const emptyMineBody =
      'Décrivez le service dont vous avez besoin : cela prend deux minutes.';
  static const notVerifiedHint = 'Faites vérifier votre compte pour publier une offre.';
  static const draftFallback = 'Offre en préparation';

  static String statusLabel(OfferStatus status) => switch (status) {
        OfferStatus.draft => 'Brouillon',
        OfferStatus.inReview => 'En cours de vérification',
        OfferStatus.published => 'Publiée',
        OfferStatus.booked => 'Réservée',
        OfferStatus.refused => 'Refusée',
        OfferStatus.withdrawn => 'Retirée',
        OfferStatus.closed => 'Terminée',
      };

  // Creation
  static const next = 'Continuer';
  static const publish = "Publier l'offre";
  static const categoryTitle = 'Quel service cherchez-vous ?';
  static const noCategory = 'Aucun service disponible pour le moment.';
  static const dutiesTitle = 'Que faut-il faire ?';
  static const whenTitle = 'Quand ?';
  static const dateLabel = 'Date';
  static const startLabel = 'Heure de début';
  static const durationLabel = 'Durée';
  static const payTitle = 'Quelle rémunération ?';
  static const payLabel = 'Montant';
  static const noteTitle = 'Une précision ? (facultatif)';
  static const noteLabel = 'Précision';
  static const noteReminder =
      "N'indiquez ni numéro de téléphone, ni adresse, ni information médicale.";
  static const summaryTitle = 'Vérifiez votre offre';
  static const placeLabel = 'Lieu';
  static const sentPublished = 'Offre publiée.';
  static const backToOffers = 'Retour à mes offres';

  static String suggestion(int min, int max) =>
      'Suggestion : ${formatAmount(min)} à ${formatXof(max)}';

  static String sentForReview(int hours) => 'Offre envoyée. Nous la vérifions sous $hours h.';

  // Detail
  static const offerNotFound = 'Cette offre n’existe plus.';
  static const editAction = 'Modifier';
  static const deleteAction = 'Supprimer';
  static const deleteTitle = 'Supprimer ce brouillon ?';
  static const withdrawAction = "Retirer l'offre";
  static const withdrawTitle = 'Retirer cette offre ?';
  static const withdrawBody = 'Les mini-jobbers ne la verront plus.';
  static const withdrawBookedBody = 'La réservation avec le jobber choisi sera annulée.';
  static const copyAction = 'Créer une offre semblable';
  static const reasonLabel = 'Motif';
}

/// French messages for the jobber app (informal "tu").
abstract final class JobberCopy {
  static const title = 'Offres';
  static const subtitle = 'Des missions publiées par des ménages vérifiés.';
  static const emptyBody = 'Reviens bientôt : de nouvelles offres sont publiées chaque jour.';
  static const communeLabel = 'Commune';
  static const allCommunes = 'Toutes les communes';
  static const empty = 'Aucune offre pour le moment.';
  static const emptyInCommune = 'Aucune offre dans cette commune pour le moment.';
  static const seeMore = 'Voir plus';
  static const retry = 'Réessayer';
  static const signOut = 'Se déconnecter';
  static const tasks = 'Tâches';
  static const whenLabel = 'Quand';
  static const durationLabel = 'Durée';
  static const payLabel = 'Rémunération';
  static const placeLabel = 'Lieu';
  static const noteLabel = 'Précision';
  static const addressNotice =
      "L'adresse exacte est communiquée seulement après une réservation confirmée.";
  static const comingSoon = 'Tu pourras bientôt postuler aux offres.';
}
