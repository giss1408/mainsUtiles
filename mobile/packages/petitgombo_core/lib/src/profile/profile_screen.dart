import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/models.dart';
import '../app/app_role.dart';
import '../app/providers.dart';
import '../app/spacing.dart';
import '../app/theme.dart';
import '../info/info_screens.dart';
import '../verification/screens/checklist_screen.dart';
import '../verification/verification_controller.dart';
import '../verification/verification_models.dart';
import '../widgets/brand.dart';
import '../widgets/ui_kit.dart';

/// The signed-in account, as the server knows it.
final meProvider = FutureProvider.autoDispose<Me>(
  (ref) => ref.watch(sessionProvider).authorized(ref.watch(apiClientProvider).me),
);

/// `+2250708091011` becomes `+225 07 •• •• •• 11`: enough to recognise, not to copy.
String maskPhone(String phone) {
  if (phone.length < 8) return phone;
  final head = phone.substring(0, phone.length - 10 < 0 ? 0 : phone.length - 10);
  final local = phone.substring(head.length);
  return '$head ${local.substring(0, 2)} •• •• •• ${local.substring(local.length - 2)}'.trim();
}

abstract final class ProfileCopy {
  static const title = 'Profil';
  static const householder = 'Ménage';
  static const jobber = 'Mini-jobber';
  static const account = 'Compte';
  static const phone = 'Téléphone';
  static const verification = 'Vérification du compte';
  static const verified = 'Compte vérifié';
  static const notVerified = 'À compléter';
  static const trust = 'Confiance';
  static const phoneConfirmed = 'Téléphone confirmé';
  static const identityVerified = 'Identité vérifiée';
  static const addressVerified = 'Adresse vérifiée';
  static const guarantorConfirmed = 'Garant confirmé';
  static const contactConfirmed = 'Personne de confiance confirmée';
  static const briefingDone = 'Consignes de sécurité vues';
  static const reviews = 'Avis reçus';
  static const noReview = 'Aucun avis pour le moment';
  static const noReviewBodyVous = 'Les avis apparaîtront ici après vos premières missions.';
  static const noReviewBodyTu = 'Les avis apparaîtront ici après tes premières missions.';
  static const learn = 'Comprendre';
  static const legal = 'Informations';
  static const signOut = 'Se déconnecter';
  static String version(String v) => 'petitGombo · version $v';
}

/// The account, the explanations and the legal notices, and the way out.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key, required this.onSignOut});

  final VoidCallback onSignOut;

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final role = ref.watch(appRoleProvider);
    final me = ref.watch(meProvider);
    final phone = me.valueOrNull?.phone;
    final householder = role == AppRole.householder;
    final checklist = ref.watch(verificationControllerProvider).checklist;
    final verified = checklist?.verified ?? false;
    final badges = [
      (ProfileCopy.phoneConfirmed, true),
      if (householder) ...[
        (ProfileCopy.identityVerified, checklist?.identity.status == StepStatus.confirmed),
        (ProfileCopy.addressVerified, checklist?.address.status == StepStatus.confirmed),
      ] else ...[
        (ProfileCopy.identityVerified, checklist?.identity.status == StepStatus.confirmed),
        (ProfileCopy.guarantorConfirmed, checklist?.guarantor.status == StepStatus.confirmed),
        (ProfileCopy.contactConfirmed, checklist?.trustedContact.status == StepStatus.confirmed),
        (ProfileCopy.briefingDone, checklist?.briefing.status == StepStatus.confirmed),
      ],
    ];

    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Gaps.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(ProfileCopy.title, style: theme.textTheme.headlineMedium),
                const SizedBox(height: Gaps.lg),
                AppCard(
                  child: Row(
                    children: [
                      const CircleAvatar(
                        radius: 28,
                        backgroundColor: AppColors.primarySoft,
                        child: Icon(Icons.person, color: AppColors.primary, size: 30),
                      ),
                      const SizedBox(width: Gaps.lg),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              householder ? ProfileCopy.householder : ProfileCopy.jobber,
                              style: theme.textTheme.titleMedium,
                            ),
                            const SizedBox(height: Gaps.xs),
                            Text(
                              phone == null ? '…' : maskPhone(phone),
                              style:
                                  theme.textTheme.bodyMedium!.copyWith(color: AppColors.textMuted),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SectionHeader(ProfileCopy.trust),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // No mission has taken place yet, so there is nothing to average.
                      const StarRating(average: 0, count: 0, size: 22),
                      const SizedBox(height: Gaps.md),
                      for (final (label, earned) in badges)
                        Padding(
                          padding: const EdgeInsets.only(top: Gaps.xs),
                          child: MetaChip(
                            icon: earned ? Icons.check_circle : Icons.radio_button_unchecked,
                            label: earned
                                ? label
                                : '$label : ${ProfileCopy.notVerified.toLowerCase()}',
                          ),
                        ),
                    ],
                  ),
                ),
                RowGroup(
                  children: [
                    NavRow(
                      icon: Icons.reviews_outlined,
                      label: ProfileCopy.reviews,
                      onTap: () => _open(context, ReviewsScreen(role: role)),
                    ),
                  ],
                ),
                if (householder) ...[
                  const SectionHeader(ProfileCopy.account),
                  RowGroup(
                    children: [
                      NavRow(
                        icon: verified ? Icons.verified_user : Icons.verified_user_outlined,
                        label: ProfileCopy.verification,
                        detail: verified ? ProfileCopy.verified : ProfileCopy.notVerified,
                        onTap: () => _open(
                          context,
                          ChecklistScreen(onBack: () => Navigator.of(context).pop()),
                        ),
                      ),
                    ],
                  ),
                ],
                const SectionHeader(ProfileCopy.learn),
                RowGroup(
                  children: [
                    NavRow(
                      icon: Icons.lightbulb_outline,
                      label: HowItWorksScreen.title,
                      onTap: () => _open(context, HowItWorksScreen(role: role)),
                    ),
                    NavRow(
                      icon: Icons.shield_outlined,
                      label: SafetyScreen.title,
                      onTap: () => _open(context, SafetyScreen(role: role)),
                    ),
                    NavRow(
                      icon: Icons.support_agent_outlined,
                      label: HelpScreen.title,
                      onTap: () => _open(context, const HelpScreen()),
                    ),
                  ],
                ),
                const SectionHeader(ProfileCopy.legal),
                RowGroup(
                  children: [
                    NavRow(
                      icon: Icons.lock_outline,
                      label: PrivacyScreen.title,
                      onTap: () => _open(context, const PrivacyScreen()),
                    ),
                    NavRow(
                      icon: Icons.description_outlined,
                      label: TermsScreen.title,
                      onTap: () => _open(context, const TermsScreen()),
                    ),
                  ],
                ),
                const SizedBox(height: Gaps.xl),
                OutlinedButton.icon(
                  onPressed: onSignOut,
                  icon: const Icon(Icons.logout),
                  label: const Text(ProfileCopy.signOut),
                ),
                const SizedBox(height: Gaps.lg),
                Text(
                  ProfileCopy.version(LegalConfig.appVersion),
                  style: theme.textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The reviews received. Reviews come with completed missions, which do not
/// exist yet, so this shows the empty state only.
class ReviewsScreen extends StatelessWidget {
  const ReviewsScreen({super.key, required this.role});

  final AppRole role;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(ProfileCopy.reviews, style: theme.textTheme.titleMedium)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Gaps.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const AppCard(child: StarRating(average: 0, count: 0, size: 24)),
              EmptyState(
                icon: Icons.reviews_outlined,
                title: ProfileCopy.noReview,
                body: role == AppRole.householder
                    ? ProfileCopy.noReviewBodyVous
                    : ProfileCopy.noReviewBodyTu,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
