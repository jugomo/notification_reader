import 'package:flutter/material.dart';

import 'encryption_util.dart';

class NotifTile extends StatelessWidget {
  final Map<String, dynamic> data;
  final String ownerUid;
  const NotifTile({super.key, required this.data, required this.ownerUid});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isFcm = data['source'] == 'fcm';
    final title =
        EncryptionUtil.decryptForUid(data['title'] as String? ?? '', ownerUid);
    final body =
        EncryptionUtil.decryptForUid(data['body'] as String? ?? '', ownerUid);
    final appName = EncryptionUtil.decryptForUid(
        data['appName'] as String? ?? (isFcm ? 'FCM' : ''), ownerUid);
    final receivedAt = data['receivedAt'] as String? ?? '';

    String timeLabel = '';
    try {
      final dt = DateTime.parse(receivedAt).toLocal();
      timeLabel =
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {}

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isFcm
                    ? colors.secondaryContainer
                    : colors.tertiaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                isFcm ? Icons.cloud : Icons.phone_android,
                size: 18,
                color: isFcm ? colors.secondary : colors.tertiary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (appName.isNotEmpty)
                        Text(
                          appName,
                          style: TextStyle(
                            fontSize: 11,
                            color: colors.outline,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      const Spacer(),
                      Text(
                        timeLabel,
                        style: TextStyle(fontSize: 11, color: colors.outline),
                      ),
                    ],
                  ),
                  if (title.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(title,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ],
                  if (body.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      body,
                      style: TextStyle(
                          fontSize: 13, color: colors.onSurfaceVariant),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
