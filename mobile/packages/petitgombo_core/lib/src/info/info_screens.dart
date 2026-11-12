import 'package:flutter/material.dart';

import '../app/app_role.dart';
import '../app/spacing.dart';
import '../app/theme.dart';
import '../widgets/message_banner.dart';
import '../widgets/ui_kit.dart';

/// Legal details that are not decided yet. Replace every bracketed value, have
/// the notice reviewed, then set [reviewed] to true to remove the warning.
abstract final class LegalConfig {
  static const controllerName = '[à définir : responsable du traitement]';
  static const contact = '[à définir : adresse de contact]';
  static const retention = '[à définir : durées de conservation]';
  static const reviewed = false;
  static const appVersion = '0.1.0';
}

class InfoSection {
  const InfoSection(this.icon, this.title, this.body);

  final IconData icon;
  final String title;
  final String body;
}

/// A titled page of short sections, each with an icon.
class InfoScreen extends StatelessWidget {
  const InfoScreen({
    super.key,
    required this.title,
    required this.sections,
    this.intro,
    this.warning,
  });

  final String title;
  final String? intro;
  final String? warning;
  final List<InfoSection> sections;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(title, style: theme.textTheme.titleMedium)),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(Gaps.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (warning != null) ...[
                    MessageBanner(message: warning!),
                    const SizedBox(height: Gaps.lg),
                  ],
                  if (intro != null) ...[
                    Text(intro!, style: theme.textTheme.bodyLarge),
                    const SizedBox(height: Gaps.lg),
                  ],
                  for (final section in sections)
                    AppCard(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          IconTile(icon: section.icon),
                          const SizedBox(width: Gaps.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(section.title, style: theme.textTheme.titleMedium),
                                const SizedBox(height: Gaps.xs),
                                Text(section.body, style: theme.textTheme.bodyMedium),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

const _draftWarning = 'Version provisoire, à faire valider par un juriste avant le lancement.';

/// What is collected, why, who sees it, and the user's rights. Written with
/// "vous" in both apps, as a formal notice.
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  static const title = 'Confidentialité et données';

  @override
  Widget build(BuildContext context) {
    return const InfoScreen(
      title: title,
      warning: LegalConfig.reviewed ? null : _draftWarning,
      intro: 'Voici, en clair, ce que petitGombo fait de vos données.',
      sections: [
        InfoSection(
          Icons.inventory_2_outlined,
          'Ce que nous collectons',
          'Votre numéro de téléphone et le modèle de votre téléphone. Pour un ménage : les photos '
              "de la pièce d'identité, un selfie, un justificatif de domicile, la commune, le "
              'quartier et la position du domicile. Les offres que vous publiez.',
        ),
        InfoSection(
          Icons.flag_outlined,
          'Pourquoi',
          "Créer et protéger votre compte, vérifier l'identité et l'adresse des ménages pour la "
              'sécurité des mini-jobbers, et publier les offres.',
        ),
        InfoSection(
          Icons.visibility_outlined,
          'Qui peut les voir',
          "Seul le personnel habilité de petitGombo. Chaque ouverture d'une photo est enregistrée. "
              "Un mini-jobber ne voit d'une offre que la commune et le quartier : jamais "
              "l'adresse, la position, le nom ni le numéro du ménage.",
        ),
        InfoSection(
          Icons.enhanced_encryption_outlined,
          'Comment elles sont protégées',
          'Les photos et les informations sensibles sont chiffrées. La connexion est liée à votre '
              'téléphone : un autre appareil doit être confirmé par notre équipe.',
        ),
        InfoSection(
          Icons.schedule_outlined,
          'Combien de temps',
          'Durées de conservation : ${LegalConfig.retention}.',
        ),
        InfoSection(
          Icons.how_to_reg_outlined,
          'Vos droits',
          'Vous pouvez demander à consulter, corriger ou supprimer vos données. '
              'Contact : ${LegalConfig.contact}.',
        ),
        InfoSection(
          Icons.apartment_outlined,
          'Responsable du traitement',
          LegalConfig.controllerName,
        ),
      ],
    );
  }
}

class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  static const title = "Conditions d'utilisation";

  @override
  Widget build(BuildContext context) {
    return const InfoScreen(
      title: title,
      warning: 'Les conditions complètes sont en cours de rédaction. '
          "Elles seront publiées ici avant l'ouverture du service.",
      intro: 'Les règles déjà en vigueur :',
      sections: [
        InfoSection(Icons.cake_outlined, '18 ans ou plus', 'Le service est réservé aux adultes.'),
        InfoSection(
          Icons.person_outline,
          'Un compte par personne',
          'Un compte est personnel et lié à un seul téléphone. Il ne se prête pas.',
        ),
        InfoSection(
          Icons.forum_outlined,
          "Tout se passe dans l'application",
          "Une offre ne contient ni numéro de téléphone, ni adresse, ni demande sur l'âge ou "
              "l'apparence. Les offres sont vérifiées.",
        ),
        InfoSection(
          Icons.gavel_outlined,
          'En cas de manquement',
          'Une offre peut être refusée ou retirée, et un compte suspendu par notre équipe.',
        ),
      ],
    );
  }
}

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  static const title = 'Aide et contact';

  @override
  Widget build(BuildContext context) {
    return const InfoScreen(
      title: title,
      sections: [
        InfoSection(
          Icons.shield_outlined,
          'Votre code reste secret',
          'Le personnel de petitGombo ne vous demandera jamais votre code de confirmation, '
              'ni par téléphone, ni par message.',
        ),
        InfoSection(
          Icons.phonelink_setup_outlined,
          'Nouveau téléphone',
          "Installez l'application sur le nouveau téléphone et saisissez votre numéro : "
              'notre équipe confirme le changement.',
        ),
        InfoSection(
          Icons.support_agent_outlined,
          'Nous écrire',
          'Contact : ${LegalConfig.contact}.',
        ),
      ],
    );
  }
}

class HowItWorksScreen extends StatelessWidget {
  const HowItWorksScreen({super.key, required this.role});

  final AppRole role;

  static const title = 'Comment ça marche';

  @override
  Widget build(BuildContext context) {
    return InfoScreen(
      title: title,
      sections: role == AppRole.householder
          ? const [
              InfoSection(
                Icons.verified_user_outlined,
                '1. Faites vérifier votre compte',
                "Pièce d'identité, justificatif de domicile et position du domicile, "
                    'confirmés par notre équipe.',
              ),
              InfoSection(
                Icons.edit_note,
                '2. Créez une offre',
                'Le service, les tâches, la date, la durée et la rémunération.',
              ),
              InfoSection(
                Icons.fact_check_outlined,
                '3. Nous la vérifions',
                'Votre première offre est toujours relue par une personne. '
                    'Les suivantes sont publiées tout de suite si rien ne pose question.',
              ),
              InfoSection(
                Icons.groups_outlined,
                '4. Les mini-jobbers la voient',
                'Ils voient la commune et le quartier, jamais votre adresse. '
                    'Les candidatures et les réservations arrivent bientôt.',
              ),
            ]
          : const [
              InfoSection(
                Icons.verified_user_outlined,
                '1. Ton compte est confirmé',
                'Notre équipe confirme ton numéro et ton téléphone.',
              ),
              InfoSection(
                Icons.search,
                '2. Consulte les offres',
                'Chaque offre indique le service, les tâches, la date, la durée, '
                    'la rémunération, la commune et le quartier.',
              ),
              InfoSection(
                Icons.lock_outline,
                "3. L'adresse reste protégée",
                "L'adresse exacte n'est donnée qu'après une réservation confirmée.",
              ),
              InfoSection(
                Icons.upcoming_outlined,
                '4. Bientôt : postuler',
                'Tu pourras bientôt postuler aux offres depuis cette application.',
              ),
            ],
    );
  }
}

class SafetyScreen extends StatelessWidget {
  const SafetyScreen({super.key, required this.role});

  final AppRole role;

  static const title = 'Sécurité';

  @override
  Widget build(BuildContext context) {
    return InfoScreen(
      title: title,
      sections: role == AppRole.householder
          ? const [
              InfoSection(
                Icons.pin_outlined,
                'Gardez votre code pour vous',
                'Personne chez petitGombo ne vous le demandera.',
              ),
              InfoSection(
                Icons.home_outlined,
                'Votre adresse est protégée',
                "Elle n'apparaît dans aucune offre. Seuls la commune et le quartier sont visibles.",
              ),
              InfoSection(
                Icons.forum_outlined,
                "Restez dans l'application",
                "N'indiquez ni numéro de téléphone ni adresse dans une offre.",
              ),
            ]
          : const [
              InfoSection(
                Icons.pin_outlined,
                'Garde ton code pour toi',
                'Personne chez petitGombo ne te le demandera.',
              ),
              InfoSection(
                Icons.verified_user_outlined,
                'Des ménages vérifiés',
                "Seul un ménage dont l'identité et l'adresse ont été confirmées par notre équipe "
                    'peut publier une offre.',
              ),
              InfoSection(
                Icons.forum_outlined,
                "Reste dans l'application",
                "N'accepte pas une mission proposée en dehors de l'application.",
              ),
            ],
    );
  }
}

/// Quiet links under the screens shown before sign-in.
class LegalFooter extends StatelessWidget {
  const LegalFooter({super.key});

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final style = TextButton.styleFrom(
      foregroundColor: AppColors.textMuted,
      textStyle: Theme.of(context).textTheme.bodyMedium,
    );
    return Wrap(
      alignment: WrapAlignment.center,
      children: [
        TextButton(
          style: style,
          onPressed: () => _open(context, const PrivacyScreen()),
          child: const Text('Confidentialité'),
        ),
        TextButton(
          style: style,
          onPressed: () => _open(context, const TermsScreen()),
          child: const Text('Conditions'),
        ),
        TextButton(
          style: style,
          onPressed: () => _open(context, const HelpScreen()),
          child: const Text('Aide'),
        ),
      ],
    );
  }
}
