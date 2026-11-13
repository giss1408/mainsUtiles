import 'package:flutter/material.dart';

import '../../app/spacing.dart';
import '../verification_copy.dart';
import 'flow_scaffold.dart';

/// Guarantor step. Replaced by the full flow in the next task.
class GuarantorFlow extends StatelessWidget {
  const GuarantorFlow({super.key});

  @override
  Widget build(BuildContext context) {
    return const FlowScaffold(
      title: VerificationCopy.guarantorTitle,
      children: [SizedBox(height: Gaps.lg)],
    );
  }
}
