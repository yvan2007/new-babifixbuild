import 'dart:convert';

import 'package:flutter/material.dart';

import '../../babifix_design_system.dart';
import '../../user_store.dart';
import 'address_map_picker_screen.dart';

/// Écran de gestion du carnet d'adresses du client (Maison, Bureau, Chez maman…).
/// Permet d'ajouter, supprimer, renommer et définir l'adresse par défaut —
/// pour réserver une prestation à un lieu précis même en déplacement.
class MyAddressesScreen extends StatefulWidget {
  const MyAddressesScreen({super.key});

  @override
  State<MyAddressesScreen> createState() => _MyAddressesScreenState();
}

class _MyAddressesScreenState extends State<MyAddressesScreen> {
  List<Map<String, dynamic>> _addresses = [];
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await BabifixUserStore.authGet('/api/client/addresses');
      if (r.statusCode == 200 && mounted) {
        final d = jsonDecode(r.body) as Map<String, dynamic>;
        setState(() {
          _addresses = List<Map<String, dynamic>>.from(d['addresses'] ?? []);
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  IconData _iconFor(String label) {
    final l = label.toLowerCase();
    if (l.contains('maison') || l.contains('domicile') || l.contains('chez')) {
      return Icons.home_rounded;
    }
    if (l.contains('bureau') || l.contains('travail') || l.contains('boulot')) {
      return Icons.work_rounded;
    }
    if (l.contains('école') || l.contains('ecole') || l.contains('fac')) {
      return Icons.school_rounded;
    }
    return Icons.place_rounded;
  }

  Future<void> _addAddress() async {
    // 1) Choisir le lieu sur la carte (réutilise le picker existant).
    final picked = await Navigator.of(context).push<PickedAddress>(
      MaterialPageRoute(builder: (_) => const AddressMapPickerScreen()),
    );
    if (picked == null || !mounted) return;

    // 2) Demander un nom (Maison, Bureau…).
    final labelCtrl = TextEditingController();
    final label = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nommer ce lieu'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: labelCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Maison, Bureau, Chez maman…',
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
                for (final s in ['Maison', 'Bureau', 'Chez maman'])
                  ActionChip(
                    label: Text(s),
                    onPressed: () => labelCtrl.text = s,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              picked.label,
              style: TextStyle(
                fontSize: 12,
                color: BabifixDesign.navy.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, labelCtrl.text.trim()),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    if (label == null || label.isEmpty) return;

    setState(() => _busy = true);
    try {
      await BabifixUserStore.authPost(
        '/api/client/addresses',
        body: jsonEncode({
          'label': label,
          'latitude': picked.latitude,
          'longitude': picked.longitude,
          'address_label': picked.label,
          'is_default': _addresses.isEmpty,
        }),
      );
      await _load();
      if (mounted) {
        _snack('Lieu « $label » enregistré.', BabifixDesign.success);
      }
    } catch (_) {
      if (mounted) _snack('Échec de l\'enregistrement.', BabifixDesign.error);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _setDefault(Map<String, dynamic> a) async {
    setState(() => _busy = true);
    try {
      await BabifixUserStore.authPatch(
        '/api/client/addresses/${a['id']}',
        body: jsonEncode({'is_default': true}),
      );
      await _load();
    } catch (_) {}
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _delete(Map<String, dynamic> a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer ce lieu ?'),
        content: Text('« ${a['label']} » sera retiré de votre carnet.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: BabifixDesign.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await BabifixUserStore.authDelete('/api/client/addresses/${a['id']}');
      await _load();
    } catch (_) {}
    if (mounted) setState(() => _busy = false);
  }

  void _snack(String msg, Color c) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: c),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mes adresses'),
        backgroundColor: BabifixDesign.navy,
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : _addAddress,
        backgroundColor: BabifixDesign.cyan,
        foregroundColor: BabifixDesign.navy,
        icon: const Icon(Icons.add_location_alt_rounded),
        label: const Text('Ajouter'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _addresses.isEmpty
              ? _emptyState()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                    itemCount: _addresses.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _addressCard(_addresses[i]),
                  ),
                ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.location_off_rounded,
                size: 64, color: BabifixDesign.navy.withValues(alpha: 0.25)),
            const SizedBox(height: 16),
            const Text('Aucune adresse enregistrée',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(
              'Enregistrez votre Maison, votre Bureau… pour réserver une '
              'prestation au bon endroit, même quand vous êtes en déplacement.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: BabifixDesign.navy.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _addressCard(Map<String, dynamic> a) {
    final isDefault = a['is_default'] == true;
    final label = '${a['label'] ?? ''}';
    final addr = '${a['address_label'] ?? ''}';
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDefault
              ? BabifixDesign.cyan
              : BabifixDesign.navy.withValues(alpha: 0.08),
          width: isDefault ? 1.6 : 1,
        ),
        boxShadow: BabifixDesign.cardShadow(true),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: BabifixDesign.cyan.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(_iconFor(label), color: BabifixDesign.navy),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 15)),
                      ),
                      if (isDefault) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: BabifixDesign.cyan.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text('Par défaut',
                              style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  color: BabifixDesign.navy)),
                        ),
                      ],
                    ],
                  ),
                  if (addr.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(addr,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12.5,
                            color: BabifixDesign.navy.withValues(alpha: 0.6))),
                  ],
                ],
              ),
            ),
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert_rounded,
                  color: BabifixDesign.navy.withValues(alpha: 0.5)),
              onSelected: (v) {
                if (v == 'default') _setDefault(a);
                if (v == 'delete') _delete(a);
              },
              itemBuilder: (_) => [
                if (!isDefault)
                  const PopupMenuItem(
                    value: 'default',
                    child: Row(children: [
                      Icon(Icons.star_rounded, size: 18),
                      SizedBox(width: 8),
                      Text('Définir par défaut'),
                    ]),
                  ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(children: [
                    Icon(Icons.delete_outline_rounded,
                        size: 18, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Supprimer', style: TextStyle(color: Colors.red)),
                  ]),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
