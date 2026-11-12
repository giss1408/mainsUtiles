import 'package:petitgombo_core/petitgombo_core.dart';

/// Every sentence the staff app shows. French only.
abstract final class StaffCopy {
  static const appName = 'petitGombo Staff';

  static const loginTitle = 'Connexion';
  static const username = 'Identifiant';
  static const password = 'Mot de passe';
  static const signIn = 'Se connecter';
  static const signOut = 'Se déconnecter';
  static const badCredentials = 'Identifiant ou mot de passe incorrect.';
  static const locked = "Trop d'essais. Réessayez dans 15 minutes.";
  static const deviceRefused = "Cet appareil n'est plus autorisé. Contactez un administrateur.";
  static const sessionExpired = 'Session expirée. Reconnectez-vous.';
  static const offline = 'Pas de connexion. Vérifiez Internet et réessayez.';
  static const forbidden = "Vous n'avez pas le droit de faire cette action.";
  static const unknownError = 'Une erreur est survenue. Réessayez.';

  static const devicePendingTitle = 'Appareil en attente';
  static const devicePending = "Appareil en attente d'activation par un administrateur.";
  static const retry = 'Réessayer';

  static const queueTitle = "Demandes d'enrôlement";
  static const empty = 'Aucune demande.';
  static const flagged = 'Signalement';
  static const tabs = [
    ('pending', 'En attente'),
    ('approved', 'À envoyer'),
    ('code_sent', 'Envoyées'),
  ];

  static const detailTitle = 'Demande';
  static const back = 'Retour';
  static const approve = 'Approuver';
  static const refuse = 'Refuser';
  static const hold = 'Mettre en attente';
  static const send = 'Envoyer par WhatsApp';
  static const resend = 'Renvoyer par WhatsApp';
  static const officialOnly = 'Envoyez uniquement depuis le WhatsApp officiel.';
  static const noWhatsApp = "WhatsApp n'est pas installé sur cet appareil.";
  static const reasonLabel = 'Motif';
  static const cancel = 'Annuler';
  static const confirm = 'Confirmer';

  static const fieldPhone = 'Téléphone';
  static const fieldRole = 'Profil';
  static const fieldKind = 'Type';
  static const fieldStatus = 'État';
  static const fieldDevice = 'Appareil';
  static const fieldIntegrity = "Vérification de l'appareil";
  static const fieldCreated = 'Reçue';
  static const fieldReason = 'Motif';
  static const fieldFlags = 'Signalements';

  static const _roles = {'jobber': 'Mini-jobber', 'householder': 'Particulier'};
  static const _kinds = {'new_account': 'Nouveau compte', 'new_device': 'Nouvel appareil'};
  static const _statuses = {
    'pending': 'En attente',
    'held': 'En vérification',
    'approved': 'Approuvée, à envoyer',
    'code_sent': 'Numéro envoyé',
    'completed': 'Terminée',
    'refused': 'Refusée',
    'expired': 'Expirée',
    'locked': 'Bloquée',
  };
  static const _flags = {
    'device_multiple_numbers': 'Cet appareil a demandé plusieurs numéros.',
  };
  static const _integrity = {'unchecked': 'Non vérifié'};

  static String role(String value) => _roles[value] ?? value;
  static String kind(String value) => _kinds[value] ?? value;
  static String status(String value) => _statuses[value] ?? value;
  static String flag(String value) => _flags[value] ?? 'Signalement : $value';
  static String integrity(String value) => _integrity[value] ?? value;

  /// `+2250708091011` becomes `+225 07 08 09 10 11`.
  static String phone(String e164) {
    if (!e164.startsWith('+225') || e164.length != 14) return e164;
    final local = e164.substring(4);
    final pairs = [for (var i = 0; i < local.length; i += 2) local.substring(i, i + 2)];
    return '+225 ${pairs.join(' ')}';
  }

  static String age(DateTime created, DateTime now) {
    final elapsed = now.difference(created);
    if (elapsed.inMinutes < 1) return "à l'instant";
    if (elapsed.inHours < 1) return 'il y a ${elapsed.inMinutes} min';
    if (elapsed.inDays < 1) return 'il y a ${elapsed.inHours} h';
    return 'il y a ${elapsed.inDays} j';
  }

  static String loginError(ApiError e) => switch (e.code) {
        'bad_credentials' => badCredentials,
        'locked' => locked,
        'unknown_device' || 'device_revoked' => deviceRefused,
        _ => actionError(e),
      };

  static String actionError(ApiError e) {
    if (e.isNetwork) return offline;
    if (e.message.isNotEmpty) return e.message;
    if (e.status == 403) return forbidden;
    return unknownError;
  }
}
