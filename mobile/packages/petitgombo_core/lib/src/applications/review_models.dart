/// One review: the stars and the words. Never who wrote it: the screen knows which side it is.
class ReviewItem {
  const ReviewItem({required this.stars, required this.comment});

  factory ReviewItem.fromJson(Map<String, dynamic> json) => ReviewItem(
        stars: (json['stars'] as num).toInt(),
        comment: (json['comment'] as String?) ?? '',
      );

  final int stars;
  final String comment;
}

/// Both reviews of a booking as one side sees them. [theirs] stays null until it is published.
class ReviewState {
  const ReviewState({this.mine, this.theirs});

  factory ReviewState.fromJson(Map<String, dynamic> json) => ReviewState(
        mine: _item(json['mine']),
        theirs: _item(json['theirs']),
      );

  static ReviewItem? _item(Object? value) =>
      value is Map ? ReviewItem.fromJson(Map<String, dynamic>.from(value)) : null;

  final ReviewItem? mine;
  final ReviewItem? theirs;
}
