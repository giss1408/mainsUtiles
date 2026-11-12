import 'package:petitgombo_core/petitgombo_core.dart';

Map<String, dynamic> categoryJson({String name = 'Ménage'}) => {
      'id': 1,
      'name': name,
      'duties': ['Dépoussiérer', 'Nettoyer la cuisine'],
      'durations_minutes': [120, 180, 240],
      'suggested_pay_min': 2000,
      'suggested_pay_max': 5000,
    };

Map<String, dynamic> limitsJson() => {
      'earliest_start': '06:00',
      'latest_end': '19:00',
      'min_pay': 1000,
      'max_pay': 100000,
      'max_days_ahead': 30,
      'note_max_length': 300,
    };

Map<String, dynamic> myOfferJson({
  String id = 'o-1',
  String status = 'draft',
  String reason = '',
  String startsAt = '2026-11-14T08:00:00Z',
  int pay = 3500,
}) =>
    {
      'id': id,
      'category_id': 1,
      'category_name': 'Ménage',
      'duties': ['Dépoussiérer'],
      'starts_at': startsAt,
      'duration_minutes': 180,
      'pay_xof': pay,
      'note': '',
      'commune': 'Cocody',
      'quartier': 'Angré',
      'status': status,
      'reason': reason,
      'created_at': '2026-11-12T10:00:00Z',
    };

Map<String, dynamic> publicOfferJson({String id = 'p-1', String commune = 'Cocody'}) => {
      'id': id,
      'category_name': 'Ménage',
      'duties': ['Dépoussiérer'],
      'starts_at': '2026-11-14T08:00:00Z',
      'duration_minutes': 180,
      'pay_xof': 3500,
      'note': 'Merci d\'apporter des gants.',
      'commune': commune,
      'quartier': 'Angré',
    };

OfferDraft draft({int pay = 3500}) => OfferDraft(
      categoryId: 1,
      duties: const ['Dépoussiérer'],
      startsAt: DateTime.utc(2026, 11, 14, 8),
      durationMinutes: 180,
      payXof: pay,
      note: '',
    );
