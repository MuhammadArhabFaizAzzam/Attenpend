import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class AttendanceHistoryScreen extends StatelessWidget {
  const AttendanceHistoryScreen({super.key});

  static final _collection = FirebaseFirestore.instance.collection(
    'attendance',
  );

  Color _getAvatarColor(String name) {
    if (name.trim().isEmpty) {
      return Colors.blueGrey;
    }

    final hash = name.codeUnits.fold<int>(
      0,
      (previous, element) => previous + element,
    );
    return Colors.primaries[hash % Colors.primaries.length];
  }

  Future<void> _editDocument(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) async {
    final data = document.data();
    final nameController = TextEditingController(
      text: (data['name'] ?? '').toString(),
    );
    final addressController = TextEditingController(
      text: (data['address'] ?? '').toString(),
    );
    final descriptionController = TextEditingController(
      text: (data['description'] ?? '').toString(),
    );
    final datetimeController = TextEditingController(
      text: (data['datetime'] ?? '').toString(),
    );

    final shouldSave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Edit Attendance'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _EditField(controller: nameController, label: 'Nama'),
                _EditField(controller: addressController, label: 'Alamat'),
                _EditField(
                  controller: descriptionController,
                  label: 'Keterangan',
                ),
                _EditField(
                  controller: datetimeController,
                  label: 'Tanggal / waktu',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Simpan'),
            ),
          ],
        );
      },
    );

    if (shouldSave != true) {
      _disposeControllers([
        nameController,
        addressController,
        descriptionController,
        datetimeController,
      ]);
      return;
    }

    try {
      await document.reference.update({
        'name': nameController.text.trim(),
        'address': addressController.text.trim(),
        'description': descriptionController.text.trim(),
        'datetime': datetimeController.text.trim(),
      });
      if (context.mounted) {
        _showMessage(context, 'Data berhasil diperbarui.', Colors.green);
      }
    } catch (error) {
      if (context.mounted) {
        _showMessage(context, 'Gagal memperbarui data: $error', Colors.red);
      }
    } finally {
      _disposeControllers([
        nameController,
        addressController,
        descriptionController,
        datetimeController,
      ]);
    }
  }

  Future<void> _deleteDocument(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Hapus data?'),
        content: const Text('Data attendance ini akan dihapus permanen.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    try {
      await document.reference.delete();
      if (context.mounted) {
        _showMessage(context, 'Data berhasil dihapus.', Colors.green);
      }
    } catch (error) {
      if (context.mounted) {
        _showMessage(context, 'Gagal menghapus data: $error', Colors.red);
      }
    }
  }

  void _disposeControllers(List<TextEditingController> controllers) {
    for (final controller in controllers) {
      controller.dispose();
    }
  }

  void _showMessage(BuildContext context, String message, Color color) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message), backgroundColor: color));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Attendance History')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _collection.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Text('Gagal memuat riwayat: ${snapshot.error}'),
            );
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('Belum ada riwayat presensi'));
          }

          final documents = [...snapshot.data!.docs];
          documents.sort((a, b) {
            final timeA = a.data()['created_at'] as Timestamp?;
            final timeB = b.data()['created_at'] as Timestamp?;
            if (timeA == null && timeB == null) return 0;
            if (timeA == null) return 1;
            if (timeB == null) return -1;
            return timeB.compareTo(timeA);
          });

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: documents.length,
            itemBuilder: (context, index) {
              final document = documents[index];
              final data = document.data();
              final name = (data['name'] ?? 'Unknown').toString();
              final address = (data['address'] ?? '-').toString();
              final description = (data['description'] ?? '-').toString();
              final datetime = (data['datetime'] ?? '-').toString();

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(12),
                  leading: CircleAvatar(
                    backgroundColor: _getAvatarColor(name),
                    child: Text(
                      name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase(),
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  title: Text(
                    name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('$description\n$datetime\n$address'),
                  ),
                  isThreeLine: true,
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'edit') {
                        _editDocument(context, document);
                      } else {
                        _deleteDocument(context, document);
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: 'edit', child: Text('Edit')),
                      PopupMenuItem(value: 'delete', child: Text('Hapus')),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _EditField extends StatelessWidget {
  final TextEditingController controller;
  final String label;

  const _EditField({required this.controller, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}
