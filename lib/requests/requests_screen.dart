import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';

class RequestsScreen extends StatelessWidget {
  const RequestsScreen({super.key});

  String get _myUid => FirebaseAuth.instance.currentUser!.uid;

  Future<void> _setStatus(String requesterUid, String status) =>
      FirebaseDatabase.instance
          .ref('users/$_myUid/incoming_requests/$requesterUid/status')
          .set(status);

  Future<void> _delete(String requesterUid) =>
      FirebaseDatabase.instance
          .ref('users/$_myUid/incoming_requests/$requesterUid')
          .remove();

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(s.requestsTitle),
        centerTitle: true,
      ),
      body: StreamBuilder<DatabaseEvent>(
        stream: FirebaseDatabase.instance
            .ref('users/$_myUid/incoming_requests')
            .onValue,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Text(
                s.loadError,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
                textAlign: TextAlign.center,
              ),
            );
          }

          final data = snapshot.data?.snapshot.value;
          if (data == null) {
            return Center(
              child: Text(
                s.noRequests,
                style:
                    TextStyle(color: Theme.of(context).colorScheme.outline),
              ),
            );
          }

          final all = (data as Map).entries.map((e) {
            final info = Map<String, dynamic>.from(e.value as Map);
            return (uid: e.key as String, info: info);
          }).toList();

          final accepted =
              all.where((e) => e.info['status'] == 'accepted').toList();
          final pending =
              all.where((e) => e.info['status'] == 'pending').toList();
          final rejected =
              all.where((e) => e.info['status'] == 'rejected').toList();

          if (all.isEmpty) {
            return Center(
              child: Text(
                s.noRequests,
                style:
                    TextStyle(color: Theme.of(context).colorScheme.outline),
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              if (accepted.isNotEmpty) ...[
                _SectionHeader(title: s.sectionGrantedAccess),
                ...accepted.map((e) => _RequestTile(
                      email: e.info['email'] as String? ?? e.uid,
                      status: 'accepted',
                      onAccept: () {},
                      onReject: () {},
                      onRevoke: () => _setStatus(e.uid, 'rejected'),
                      onDelete: () {},
                    )),
              ],
              if (pending.isNotEmpty) ...[
                _SectionHeader(title: s.sectionPendingRequests),
                ...pending.map((e) => _RequestTile(
                      email: e.info['email'] as String? ?? e.uid,
                      status: 'pending',
                      onAccept: () => _setStatus(e.uid, 'accepted'),
                      onReject: () => _setStatus(e.uid, 'rejected'),
                      onRevoke: () {},
                      onDelete: () {},
                    )),
              ],
              if (rejected.isNotEmpty) ...[
                _SectionHeader(title: s.sectionRejected),
                ...rejected.map((e) => _RequestTile(
                      email: e.info['email'] as String? ?? e.uid,
                      status: 'rejected',
                      onAccept: () {},
                      onReject: () {},
                      onRevoke: () {},
                      onDelete: () => _delete(e.uid),
                    )),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: colors.outline,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _RequestTile extends StatelessWidget {
  final String email;
  final String status;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback onRevoke;
  final VoidCallback onDelete;

  const _RequestTile({
    required this.email,
    required this.status,
    required this.onAccept,
    required this.onReject,
    required this.onRevoke,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.person_outline),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      email,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              if (status == 'pending') ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    FilledButton.icon(
                      onPressed: onAccept,
                      icon: const Icon(Icons.check, size: 18),
                      label: Text(s.accept),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: onReject,
                      icon:
                          Icon(Icons.close, size: 18, color: colors.error),
                      label: Text(s.reject,
                          style: TextStyle(color: colors.error)),
                    ),
                  ],
                ),
              ] else if (status == 'accepted') ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: onRevoke,
                  icon: Icon(Icons.person_remove,
                      size: 18, color: colors.error),
                  label: Text(s.revokeAccess,
                      style: TextStyle(color: colors.error)),
                ),
              ] else if (status == 'rejected') ...[
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: onDelete,
                  icon: Icon(Icons.delete_outline,
                      size: 18, color: colors.outline),
                  label: Text(s.deleteEntry,
                      style: TextStyle(color: colors.outline)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
