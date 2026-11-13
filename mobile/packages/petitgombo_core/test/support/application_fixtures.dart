Map<String, dynamic> trustJson({int jobsDone = 3}) =>
    {'tier': 'H1', 'jobs_done': jobsDone, 'rating': null};

Map<String, dynamic> applicationItemJson({
  String id = 'a-1',
  String status = 'pending',
  String message = 'Bonjour',
  String offerStatus = 'published',
  Map<String, dynamic>? booking,
}) =>
    {
      'id': id,
      'status': status,
      'message': message,
      'created_at': '2026-11-12T10:00:00Z',
      'offer': {
        'id': 'o-1',
        'category_name': 'Ménage',
        'starts_at': '2026-11-14T08:00:00Z',
        'duration_minutes': 180,
        'pay_xof': 3500,
        'commune': 'Cocody',
        'quartier': 'Angré',
        'status': offerStatus,
      },
      'booking': booking,
    };

Map<String, dynamic> applicantJson({String id = 'a-1', String name = 'Awa'}) => {
      'id': id,
      'first_name': name,
      'tier': 'J1',
      'jobs_done': 2,
      'rating': null,
      'message': 'Disponible le matin.',
      'created_at': '2026-11-12T10:00:00Z',
    };

Map<String, dynamic> acceptedJson() => {
      'id': 'b-1',
      'status': 'accepted',
      'jobber_first_name': 'Awa',
      'category_name': 'Ménage',
      'starts_at': '2026-11-14T08:00:00Z',
      'pay_xof': 3500,
    };

Map<String, dynamic> jobberBookingJson() => {
      'id': 'b-1',
      'status': 'accepted',
      'category_name': 'Ménage',
      'starts_at': '2026-11-14T08:00:00Z',
      'duration_minutes': 180,
      'pay_xof': 3500,
      'commune': 'Cocody',
      'quartier': 'Angré',
      'address_available_from': '2026-11-14T05:00:00Z',
      'payment': 'pending',
    };

Map<String, dynamic> methodJson({int id = 1, String provider = 'wave'}) => {
      'id': id,
      'provider': provider,
      'provider_label': provider == 'wave' ? 'Wave' : 'MTN MoMo',
      'number': '+2250101010101',
      'account_name': 'petitGombo',
    };

Map<String, dynamic> bookingDetailJson({
  String status = 'accepted',
  Map<String, dynamic>? payment,
  Map<String, dynamic>? jobber,
  bool cancellable = true,
}) =>
    {
      'id': 'b-1',
      'status': status,
      'amount_xof': 3500,
      'fee_xof': 0,
      'pay_deadline': '2026-11-14T02:00:00Z',
      'methods': [methodJson(), methodJson(id: 2, provider: 'mtn_momo')],
      'payment': payment,
      'jobber': jobber ?? {'first_name': 'Awa'},
      'cancellable': cancellable,
    };

Map<String, dynamic> addressJson() => {
      'latitude': 5.3599,
      'longitude': -3.9871,
      'commune': 'Cocody',
      'quartier': 'Angré',
    };
