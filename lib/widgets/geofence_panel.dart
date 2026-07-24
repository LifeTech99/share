import 'package:flutter/material.dart';

class GeofencePanel extends StatelessWidget {
  final bool visible;
  final VoidCallback onCancel;
  final VoidCallback onSave;
  final VoidCallback onDelete;

  const GeofencePanel({
    super.key,
    required this.visible,
    required this.onCancel,
    required this.onSave,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 300),
      left: 0,
      right: 0,
      bottom: visible ? 0 : -120,
      child: Container(
        height: MediaQuery.of(context).size.height * 0.10,
        color: Colors.white,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            TextButton(
              onPressed: onCancel,
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: onSave,
              child: const Text("Save"),
            ),
            TextButton(
              onPressed: onDelete,
              child: const Text("Delete"),
            ),
          ],
        ),
      ),
    );
  }
}
