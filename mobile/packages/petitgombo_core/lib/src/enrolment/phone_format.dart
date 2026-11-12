/// Returns the E.164 form (+225 followed by 10 digits) of an Ivorian number
/// typed in local or international format, or null when it is not one.
String? normaliseIvorianPhone(String input) {
  var digits = input.replaceAll(RegExp(r'[\s\-.()]'), '');
  if (digits.startsWith('+225')) {
    digits = digits.substring(4);
  } else if (digits.startsWith('00225')) {
    digits = digits.substring(5);
  } else if (digits.startsWith('+') || digits.startsWith('00')) {
    return null;
  }
  if (!RegExp(r'^0\d{9}$').hasMatch(digits)) return null;
  return '+225$digits';
}
