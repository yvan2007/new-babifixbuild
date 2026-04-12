import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../babifix_design_system.dart';
import '../../shared/widgets/address_search_field.dart';
import '../../shared/widgets/babifix_osm_map.dart';
import '../../shared/widgets/message_with_photos_field.dart';
import '../../shared/widgets/payment_method_logo.dart';

/// Flow de réservation en 4 étapes :
/// 0 → Date & heure  1 → Adresse  2 → Récapitulatif  3 → Confirmation
class BookingFlowScreen extends StatefulWidget {
  const BookingFlowScreen({
    super.key,
    required this.serviceTitle,
    required this.servicePrice,
    this.onConfirm,
  });

  final String serviceTitle;
  final int servicePrice;
  final Future<bool> Function(Map<String, dynamic> data)? onConfirm;

  @override
  State<BookingFlowScreen> createState() => _BookingFlowScreenState();
}

class _BookingFlowScreenState extends State<BookingFlowScreen> {
  int _step = 0;

  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  final _addressCtrl = TextEditingController();
  final _msgCtrl = TextEditingController();
  final _prixProposeCtrl = TextEditingController();
  String _paymentType = 'ESPECES';
  String _mmOperator = 'ORANGE_MONEY';
  bool _submitting = false;
  bool _confirmed = false;

  LatLng _mapPin = BabifixOsmLocationPicker.defaultCenter;
  /// `true` après un tap sur la carte ou « Ma position » — sinon on n'envoie pas lat/lng à l'API.
  bool _mapPinFromUser = false;
  List<Uint8List> _photos = [];

  static const _steps = ['Date', 'Adresse', 'Récapitulatif', 'Confirmation'];

  @override
  void dispose() {
    _addressCtrl.dispose();
    _msgCtrl.dispose();
    _prixProposeCtrl.dispose();
    super.dispose();
  }

  void _goTo(int step) {
    setState(() => _step = step);
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    final prixProposeText = _prixProposeCtrl.text.trim();
    final prixPropose = prixProposeText.isNotEmpty
        ? double.tryParse(prixProposeText.replaceAll(RegExp(r'[^\d.]'), ''))
        : null;
    final data = <String, dynamic>{
      'date': _selectedDate?.toIso8601String() ?? '',
      'time': _selectedTime?.format(context) ?? '',
      'address': _addressCtrl.text.trim(),
      'message': _msgCtrl.text.trim(),
      'payment_type': _paymentType,
      if (prixPropose != null && prixPropose > 0) 'price_fcfa': prixPropose,
    };
    if (_mapPinFromUser) {
      data['latitude'] = _mapPin.latitude;
      data['longitude'] = _mapPin.longitude;
    }
    if (_photos.isNotEmpty) {
      data['photo_attachments'] = _photos
          .map((b) => 'data:image/jpeg;base64,${base64Encode(b)}')
          .toList();
    }
    if (_paymentType == 'MOBILE_MONEY') {
      data['mobile_money_operator'] = _mmOperator;
    }
    bool ok = false;
    if (widget.onConfirm != null) {
      ok = await widget.onConfirm!(data);
    } else {
      await Future.delayed(const Duration(seconds: 1));
      ok = true;
    }
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _confirmed = ok;
    });
    if (ok) _goTo(3);
  }

  Widget _buildCurrentStep(BuildContext context, Color text, Color sub) {
    switch (_step) {
      case 0:
        return _StepDate(
          textColor: text,
          subColor: sub,
          selectedDate: _selectedDate,
          selectedTime: _selectedTime,
          onDateChanged: (d) => setState(() => _selectedDate = d),
          onTimeChanged: (t) => setState(() => _selectedTime = t),
          onNext: () {
            if (_selectedDate == null || _selectedTime == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Choisissez une date et une heure.')),
              );
              return;
            }
            _goTo(1);
          },
        );
      case 1:
        return _StepAddress(
          textColor: text,
          subColor: sub,
          addressCtrl: _addressCtrl,
          msgCtrl: _msgCtrl,
          mapPin: _mapPin,
          onMapPinChanged: (p) => setState(() {
            _mapPin = p;
            _mapPinFromUser = true;
          }),
          photos: _photos,
          onPhotosChanged: (p) => setState(() => _photos = p),
          onNext: () {
            if (_addressCtrl.text.trim().isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Renseignez votre adresse.')),
              );
              return;
            }
            _goTo(2);
          },
          onBack: () => _goTo(0),
        );
      case 2:
        return _StepSummary(
          textColor: text,
          subColor: sub,
          serviceTitle: widget.serviceTitle,
          servicePrice: widget.servicePrice,
          date: _selectedDate,
          time: _selectedTime,
          address: _addressCtrl.text,
          mapPinRegistered: _mapPinFromUser,
          photoCount: _photos.length,
          paymentType: _paymentType,
          mmOperator: _mmOperator,
          onPaymentChanged: (v) => setState(() => _paymentType = v),
          onMmOperatorChanged: (v) => setState(() => _mmOperator = v),
          onConfirm: _submit,
          onBack: () => _goTo(1),
          submitting: _submitting,
          prixProposeCtrl: _prixProposeCtrl,
        );
      default:
        return _StepDone(
          textColor: text,
          serviceTitle: widget.serviceTitle,
          onClose: () => Navigator.of(context).pop(),
        );
    }
  }

  static const _kNavy = Color(0xFF050D1A);
  static const _kBlue = Color(0xFF2563EB);
  static const _kCyan = Color(0xFF4CC9F0);

  @override
  Widget build(BuildContext context) {
    // Force dark theme for the entire booking flow so AppBar, system overlays
    // and step indicators all stay consistent regardless of phone theme.
    return Theme(
      data: ThemeData.dark().copyWith(
        colorScheme: const ColorScheme.dark(
          primary: _kBlue,
          secondary: _kCyan,
          surface: Color(0xFF0A1628),
          onSurface: Colors.white,
          onSurfaceVariant: Color(0x80FFFFFF),
        ),
        scaffoldBackgroundColor: _kNavy,
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF060E1C),
          foregroundColor: Colors.white,
          elevation: 0,
          titleTextStyle: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800),
        ),
      ),
      child: PopScope(
        canPop: _step == 0 || _step == 3,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && _step > 0 && _step < 3) {
            _goTo(_step - 1);
          }
        },
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Réserver'),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(48),
              child: _StepIndicator(steps: _steps, current: _step),
            ),
          ),
          body: SizedBox.expand(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: SizedBox.expand(
                key: ValueKey(_step),
                child: _buildCurrentStep(context, Colors.white, const Color(0x80FFFFFF)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Step indicator ────────────────────────────────────────────────────────────

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.steps, required this.current});

  final List<String> steps;
  final int current;

  @override
  Widget build(BuildContext context) {
    final divider = Theme.of(context).dividerColor;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          for (int i = 0; i < steps.length; i++) ...[
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                height: 4,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(99),
                  color: i <= current ? BabifixDesign.cyan : divider,
                ),
              ),
            ),
            if (i < steps.length - 1) const SizedBox(width: 4),
          ],
        ],
      ),
    );
  }
}

// ── Step 0 : Date ─────────────────────────────────────────────────────────────

class _StepDate extends StatelessWidget {
  const _StepDate({
    required this.textColor,
    required this.subColor,
    required this.selectedDate,
    required this.selectedTime,
    required this.onDateChanged,
    required this.onTimeChanged,
    required this.onNext,
  });

  final Color textColor;
  final Color subColor;
  final DateTime? selectedDate;
  final TimeOfDay? selectedTime;
  final ValueChanged<DateTime> onDateChanged;
  final ValueChanged<TimeOfDay> onTimeChanged;
  final VoidCallback onNext;

  static const _kNavy = Color(0xFF050D1A);
  static const _kBlue = Color(0xFF2563EB);
  static const _kBlueDark = Color(0xFF1D4ED8);
  static const _kCyan = Color(0xFF4CC9F0);

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    final dateSet = selectedDate != null;
    final timeSet = selectedTime != null;
    return Container(
      color: _kNavy,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Titre ───────────────────────────────────────────────────
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: LinearGradient(
                      colors: [_kBlue.withValues(alpha: 0.25), _kBlue.withValues(alpha: 0.08)],
                    ),
                  ),
                  child: const Icon(Icons.event_rounded, color: _kCyan, size: 22),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Date & heure',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.3),
                    ),
                    Text(
                      'Quand souhaitez-vous l\'intervention ?',
                      style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.45)),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 28),

            // ── Carte Date ──────────────────────────────────────────────
            _PremiumPickerCard(
              label: 'Date d\'intervention',
              value: dateSet ? _formatDate(selectedDate!) : 'Choisir une date',
              icon: Icons.calendar_month_rounded,
              isSet: dateSet,
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: DateTime.now().add(const Duration(days: 1)),
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 90)),
                  builder: (ctx, child) => Theme(
                    data: ThemeData.dark().copyWith(
                      colorScheme: const ColorScheme.dark(primary: _kBlue, onPrimary: Colors.white, surface: Color(0xFF0A1628)),
                    ),
                    child: child!,
                  ),
                );
                if (d != null) onDateChanged(d);
              },
            ),
            const SizedBox(height: 14),

            // ── Carte Heure ─────────────────────────────────────────────
            _PremiumPickerCard(
              label: 'Heure d\'intervention',
              value: selectedTime?.format(context) ?? 'Choisir une heure',
              icon: Icons.schedule_rounded,
              isSet: timeSet,
              onTap: () async {
                final t = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay.now(),
                  builder: (ctx, child) => Theme(
                    data: ThemeData.dark().copyWith(
                      colorScheme: const ColorScheme.dark(primary: _kBlue, onPrimary: Colors.white, surface: Color(0xFF0A1628)),
                    ),
                    child: child!,
                  ),
                );
                if (t != null) onTimeChanged(t);
              },
            ),

            const SizedBox(height: 12),
            // ── Info bulle ───────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: _kBlue.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _kBlue.withValues(alpha: 0.20)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, color: _kCyan.withValues(alpha: 0.8), size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Vous pouvez choisir jusqu\'à 3 mois à l\'avance. Le prestataire confirmera la disponibilité.',
                      style: TextStyle(fontSize: 11.5, color: Colors.white.withValues(alpha: 0.55), height: 1.4),
                    ),
                  ),
                ],
              ),
            ),

            const Spacer(),
            // ── Bouton ───────────────────────────────────────────────────
            GestureDetector(
              onTap: onNext,
              child: Container(
                width: double.infinity,
                height: 54,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [_kBlue, _kBlueDark]),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(color: _kBlue.withValues(alpha: 0.45), blurRadius: 20, offset: const Offset(0, 8)),
                  ],
                ),
                child: const Center(
                  child: Text(
                    'Continuer',
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 0.2),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PremiumPickerCard extends StatelessWidget {
  const _PremiumPickerCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.isSet,
    required this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final bool isSet;
  final VoidCallback onTap;

  static const _kBlue = Color(0xFF2563EB);
  static const _kCyan = Color(0xFF4CC9F0);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSet ? _kBlue.withValues(alpha: 0.55) : Colors.white.withValues(alpha: 0.10),
            width: isSet ? 1.5 : 1,
          ),
          boxShadow: isSet
              ? [BoxShadow(color: _kBlue.withValues(alpha: 0.15), blurRadius: 12, offset: const Offset(0, 4))]
              : [],
        ),
        child: Row(
          children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: LinearGradient(
                  colors: isSet
                      ? [_kBlue.withValues(alpha: 0.35), _kBlue.withValues(alpha: 0.12)]
                      : [Colors.white.withValues(alpha: 0.08), Colors.white.withValues(alpha: 0.03)],
                ),
              ),
              child: Icon(icon, color: isSet ? _kCyan : Colors.white.withValues(alpha: 0.35), size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(fontSize: 11.5, color: Colors.white.withValues(alpha: 0.40), fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: isSet ? Colors.white : Colors.white.withValues(alpha: 0.35),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              isSet ? Icons.check_circle_rounded : Icons.arrow_forward_ios_rounded,
              color: isSet ? _kCyan : Colors.white.withValues(alpha: 0.25),
              size: isSet ? 20 : 16,
            ),
          ],
        ),
      ),
    );
  }
}

// Old _DatePickerCard kept as dead code to not break references — replaced by _PremiumPickerCard
class _DatePickerCard extends StatelessWidget {
  const _DatePickerCard({required this.label, required this.value, required this.icon, required this.onTap});
  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => _PremiumPickerCard(label: label, value: value, icon: icon, isSet: false, onTap: onTap);
}

// ── Step 1 : Adresse ──────────────────────────────────────────────────────────

class _StepAddress extends StatelessWidget {
  const _StepAddress({
    required this.textColor,
    required this.subColor,
    required this.addressCtrl,
    required this.msgCtrl,
    required this.mapPin,
    required this.onMapPinChanged,
    required this.photos,
    required this.onPhotosChanged,
    required this.onNext,
    required this.onBack,
  });

  final Color textColor;
  final Color subColor;
  final TextEditingController addressCtrl;
  final TextEditingController msgCtrl;
  final LatLng mapPin;
  final ValueChanged<LatLng> onMapPinChanged;
  final List<Uint8List> photos;
  final ValueChanged<List<Uint8List>> onPhotosChanged;
  final VoidCallback onNext;
  final VoidCallback onBack;

  static const _kNavy = Color(0xFF050D1A);
  static const _kBlue = Color(0xFF2563EB);
  static const _kBlueDark = Color(0xFF1D4ED8);
  static const _kCyan = Color(0xFF4CC9F0);

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData.dark().copyWith(
        colorScheme: const ColorScheme.dark(
          primary: _kBlue,
          secondary: _kCyan,
          surface: Color(0xFF0A1628),
        ),
        textSelectionTheme: const TextSelectionThemeData(
          cursorColor: _kCyan,
          selectionColor: Color(0x554CC9F0),
          selectionHandleColor: _kCyan,
        ),
      ),
      child: Container(
        color: _kNavy,
        child: SingleChildScrollView(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 16,
            bottom: MediaQuery.viewInsetsOf(context).bottom + 28,
          ),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Titre ────────────────────────────────────────────────
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: LinearGradient(
                        colors: [_kBlue.withValues(alpha: 0.25), _kBlue.withValues(alpha: 0.08)],
                      ),
                    ),
                    child: const Icon(Icons.location_on_rounded, color: _kCyan, size: 22),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Lieu d\'intervention',
                          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.3),
                        ),
                        Text(
                          'Indiquez l\'adresse exacte',
                          style: TextStyle(fontSize: 12, color: Color(0x72FFFFFF)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),

              // ── Carte adresse ─────────────────────────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 20, offset: const Offset(0, 8))],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            color: _kBlue.withValues(alpha: 0.18),
                          ),
                          child: const Icon(Icons.edit_location_alt_rounded, color: _kCyan, size: 18),
                        ),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Rechercher une adresse',
                              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: Colors.white),
                            ),
                            Text(
                              'Ou touchez la carte ci-dessous',
                              style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.40)),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    BabifixAddressSearchField(
                      controller: addressCtrl,
                      onPlaceSelected: (latLng, _) => onMapPinChanged(latLng),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              // ── Carte OSM ─────────────────────────────────────────────
              Row(
                children: [
                  const Icon(Icons.map_rounded, color: _kCyan, size: 18),
                  const SizedBox(width: 6),
                  const Text(
                    'Positionnez le marqueur',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Colors.white),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _kBlue.withValues(alpha: 0.30)),
                  boxShadow: [BoxShadow(color: _kBlue.withValues(alpha: 0.12), blurRadius: 16, offset: const Offset(0, 6))],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: BabifixOsmLocationPicker(
                    marker: mapPin,
                    onMarkerMoved: onMapPinChanged,
                    height: 230,
                  ),
                ),
              ),

              const SizedBox(height: 22),

              // ── Message + Photos ──────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            color: _kBlue.withValues(alpha: 0.18),
                          ),
                          child: const Icon(Icons.chat_bubble_outline_rounded, color: _kCyan, size: 18),
                        ),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Détails du problème',
                              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: Colors.white),
                            ),
                            Text(
                              'Message + photos (optionnel)',
                              style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.40)),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    MessageWithPhotosField(
                      controller: msgCtrl,
                      photos: photos,
                      onPhotosChanged: onPhotosChanged,
                      maxPhotos: 6,
                      hint: 'Précisions, accès, contraintes…',
                      messageHeading: 'Message',
                      photosHeading: 'Photos',
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              // ── Boutons ───────────────────────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: onBack,
                      child: Container(
                        height: 52,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.07),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                        ),
                        child: const Center(
                          child: Text('Retour', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: GestureDetector(
                      onTap: onNext,
                      child: Container(
                        height: 52,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [_kBlue, _kBlueDark]),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [BoxShadow(color: _kBlue.withValues(alpha: 0.40), blurRadius: 16, offset: const Offset(0, 6))],
                        ),
                        child: const Center(
                          child: Text('Continuer', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Step 2 : Récapitulatif ────────────────────────────────────────────────────

class _StepSummary extends StatelessWidget {
  const _StepSummary({
    required this.textColor,
    required this.subColor,
    required this.serviceTitle,
    required this.servicePrice,
    required this.date,
    required this.time,
    required this.address,
    required this.mapPinRegistered,
    required this.photoCount,
    required this.paymentType,
    required this.mmOperator,
    required this.onPaymentChanged,
    required this.onMmOperatorChanged,
    required this.onConfirm,
    required this.onBack,
    required this.submitting,
    required this.prixProposeCtrl,
  });

  final Color textColor;
  final Color subColor;
  final String serviceTitle;
  final int servicePrice;
  final DateTime? date;
  final TimeOfDay? time;
  final String address;
  final bool mapPinRegistered;
  final int photoCount;
  final String paymentType;
  final String mmOperator;
  final ValueChanged<String> onPaymentChanged;
  final ValueChanged<String> onMmOperatorChanged;
  final Future<void> Function() onConfirm;
  final VoidCallback onBack;
  final bool submitting;
  final TextEditingController prixProposeCtrl;

  static const _mmIds = ['ORANGE_MONEY', 'MTN_MOMO', 'WAVE', 'MOOV'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isLight = theme.brightness == Brightness.light;
    final cardBg = isLight ? Colors.white : const Color(0xFF1A1F28);
    final sectionBg = isLight ? const Color(0xFFF8FAFC) : const Color(0xFF141920);
    final dividerColor = isLight ? const Color(0xFFE8EDF3) : const Color(0xFF252C38);

    final dateStr = date != null
        ? '${date!.day.toString().padLeft(2, '0')}/${date!.month.toString().padLeft(2, '0')}/${date!.year} — ${time?.format(context) ?? ''}'
        : '—';

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Bannière service ──────────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF0A2540), Color(0xFF0E3A65)],
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0A2540).withValues(alpha: 0.45),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: BabifixDesign.cyan.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: BabifixDesign.cyan.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.verified_rounded, size: 12, color: BabifixDesign.cyan),
                          const SizedBox(width: 5),
                          Text(
                            'Récapitulatif',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: BabifixDesign.cyan,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  serviceTitle,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: -0.4,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _BannerChip(
                      icon: Icons.calendar_today_rounded,
                      label: dateStr,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _BannerChip(
                      icon: Icons.location_on_rounded,
                      label: address.isEmpty ? 'Adresse non renseignée' : address,
                      maxWidth: 260,
                    ),
                  ],
                ),
                if (servicePrice > 0) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Tarif estimé : ',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.white.withValues(alpha: 0.7),
                          ),
                        ),
                        Text(
                          '$servicePrice FCFA',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: BabifixDesign.cyan,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ── Détails logistiques ───────────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: dividerColor),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isLight ? 0.04 : 0.18),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              children: [
                _SummaryRow2(
                  icon: Icons.event_available_rounded,
                  iconColor: const Color(0xFF6366F1),
                  iconBg: const Color(0xFFEEF2FF),
                  iconBgDark: const Color(0xFF1E1B4B),
                  label: 'Date & heure',
                  value: dateStr,
                  isLight: isLight,
                  textColor: textColor,
                  subColor: subColor,
                ),
                Divider(height: 1, color: dividerColor),
                _SummaryRow2(
                  icon: Icons.signpost_rounded,
                  iconColor: const Color(0xFF10B981),
                  iconBg: const Color(0xFFECFDF5),
                  iconBgDark: const Color(0xFF064E3B),
                  label: 'Adresse d\'intervention',
                  value: address.isEmpty ? 'Non renseignée' : address,
                  isLight: isLight,
                  textColor: textColor,
                  subColor: subColor,
                  valueMaxLines: 3,
                ),
                Divider(height: 1, color: dividerColor),
                _SummaryRow2(
                  icon: Icons.explore_rounded,
                  iconColor: const Color(0xFFF59E0B),
                  iconBg: const Color(0xFFFFFBEB),
                  iconBgDark: const Color(0xFF451A03),
                  label: 'Repère GPS',
                  value: mapPinRegistered ? 'Position enregistrée ✓' : 'Non renseigné (optionnel)',
                  isLight: isLight,
                  textColor: textColor,
                  subColor: subColor,
                ),
                if (photoCount > 0) ...[
                  Divider(height: 1, color: dividerColor),
                  _SummaryRow2(
                    icon: Icons.collections_rounded,
                    iconColor: const Color(0xFFEC4899),
                    iconBg: const Color(0xFFFDF2F8),
                    iconBgDark: const Color(0xFF4A044E),
                    label: 'Photos jointes',
                    value: '$photoCount photo${photoCount > 1 ? "s" : ""} ajoutée${photoCount > 1 ? "s" : ""}',
                    isLight: isLight,
                    textColor: textColor,
                    subColor: subColor,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ── Prix proposé (optionnel) ──────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: dividerColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isLight ? const Color(0xFFFFF7ED) : const Color(0xFF431407),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.price_change_rounded, size: 18, color: Color(0xFFF97316)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Prix proposé',
                              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: textColor)),
                          Text('Optionnel — proposez votre budget au prestataire',
                              style: TextStyle(fontSize: 11, color: subColor)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: prixProposeCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    hintText: 'ex : 15000',
                    suffixText: 'FCFA',
                    prefixIcon: const Icon(Icons.monetization_on_outlined, color: Color(0xFFF97316)),
                    filled: true,
                    fillColor: isLight ? const Color(0xFFFFFBF7) : const Color(0xFF1A1410),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: dividerColor),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFF97316), width: 2),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // ── Mode de paiement ──────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: sectionBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: dividerColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isLight ? const Color(0xFFEFF6FF) : const Color(0xFF1E3A5F),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.payments_rounded, size: 18, color: Color(0xFF3B82F6)),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Mode de paiement',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: textColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.only(left: 36),
                  child: Text(
                    'Espèces sur place ou Mobile Money (Orange, MTN, Wave, Moov).',
                    style: TextStyle(fontSize: 12, color: subColor, height: 1.35),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          IntrinsicHeight(
            child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _PaymentModeTile(
                  selected: paymentType == 'ESPECES',
                  onTap: () => onPaymentChanged('ESPECES'),
                  icon: Icons.payments_rounded,
                  title: 'Espèces',
                  subtitle: 'Au rendez-vous',
                  textColor: textColor,
                  subColor: subColor,
                  footer: const SizedBox(height: 28),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _PaymentModeTile(
                  selected: paymentType == 'MOBILE_MONEY',
                  onTap: () => onPaymentChanged('MOBILE_MONEY'),
                  icon: Icons.phone_android_rounded,
                  title: 'Mobile Money',
                  subtitle: 'Orange · MTN · Wave',
                  textColor: textColor,
                  subColor: subColor,
                  footer: const SizedBox(
                    height: 28,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: BabifixMobileMoneyLogoStrip(height: 20),
                    ),
                  ),
                ),
              ),
            ],
          ), // Row
          ), // IntrinsicHeight
          if (paymentType == 'MOBILE_MONEY') ...[
            const SizedBox(height: 14),
            Text(
              'Opérateur',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: textColor,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final id in _mmIds)
                  _MmOperatorLogoChip(
                    methodId: id,
                    selected: mmOperator == id,
                    onTap: () => onMmOperatorChanged(id),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 20),
          // ── Boutons d'action ──────────────────────────────────────────────
          Row(
            children: [
              OutlinedButton(
                onPressed: onBack,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(52, 52),
                  maximumSize: const Size(52, 52),
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Icon(Icons.arrow_back_rounded),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: submitting ? null : onConfirm,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    height: 52,
                    decoration: BoxDecoration(
                      gradient: submitting
                          ? null
                          : const LinearGradient(
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                              colors: [Color(0xFF0EA5E9), Color(0xFF4CC9F0)],
                            ),
                      color: submitting ? const Color(0xFF94A3B8) : null,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: submitting
                          ? null
                          : [
                              BoxShadow(
                                color: const Color(0xFF0EA5E9).withValues(alpha: 0.4),
                                blurRadius: 16,
                                offset: const Offset(0, 6),
                              ),
                            ],
                    ),
                    alignment: Alignment.center,
                    child: submitting
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                              SizedBox(width: 8),
                              Text(
                                'Confirmer la réservation',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                  letterSpacing: -0.2,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _PaymentModeTile extends StatelessWidget {
  const _PaymentModeTile({
    required this.selected,
    required this.onTap,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.textColor,
    required this.subColor,
    this.footer,
  });

  final bool selected;
  final VoidCallback onTap;
  final IconData icon;
  final String title;
  final String subtitle;
  final Color textColor;
  final Color subColor;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              width: selected ? 2 : 1,
              color: selected
                  ? BabifixDesign.cyan
                  : theme.dividerColor.withValues(alpha: 0.65),
            ),
            color: selected
                ? BabifixDesign.cyan.withValues(alpha: 0.08)
                : cs.surface,
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: BabifixDesign.cyan.withValues(alpha: 0.18),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 168),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            BabifixDesign.cyan.withValues(alpha: 0.2),
                            BabifixDesign.cyan.withValues(alpha: 0.05),
                          ],
                        ),
                      ),
                      child: Icon(icon, color: BabifixDesign.cyan, size: 22),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11,
                        color: subColor,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
                footer ?? const SizedBox(height: 28),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MmOperatorLogoChip extends StatelessWidget {
  const _MmOperatorLogoChip({
    required this.methodId,
    required this.selected,
    required this.onTap,
  });

  final String methodId;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              width: selected ? 2 : 1,
              color: selected
                  ? BabifixDesign.cyan
                  : theme.dividerColor.withValues(alpha: 0.6),
            ),
            color: selected
                ? BabifixDesign.cyan.withValues(alpha: 0.1)
                : cs.surface,
          ),
          child: BabifixPaymentMethodLogo(methodId: methodId, height: 30),
        ),
      ),
    );
  }
}

// ── Bannière chip (ligne d'info dans le header gradient) ─────────────────────

class _BannerChip extends StatelessWidget {
  const _BannerChip({required this.icon, required this.label, this.maxWidth});
  final IconData icon;
  final String label;
  final double? maxWidth;

  @override
  Widget build(BuildContext context) {
    Widget text = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 12,
        color: Colors.white.withValues(alpha: 0.85),
        fontWeight: FontWeight.w500,
      ),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: Colors.white.withValues(alpha: 0.6)),
        const SizedBox(width: 5),
        maxWidth != null
            ? ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth!), child: text)
            : Flexible(child: text),
      ],
    );
  }
}

// ── Ligne de détail premium ───────────────────────────────────────────────────

class _SummaryRow2 extends StatelessWidget {
  const _SummaryRow2({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.iconBgDark,
    required this.label,
    required this.value,
    required this.isLight,
    required this.textColor,
    required this.subColor,
    this.valueMaxLines,
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final Color iconBgDark;
  final String label;
  final String value;
  final bool isLight;
  final Color textColor;
  final Color subColor;
  final int? valueMaxLines;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: isLight ? iconBg : iconBgDark,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, size: 22, color: iconColor),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                    color: subColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  maxLines: valueMaxLines,
                  overflow: valueMaxLines != null ? TextOverflow.ellipsis : null,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Step 3 : Confirmation ─────────────────────────────────────────────────────

class _StepDone extends StatelessWidget {
  const _StepDone({
    required this.textColor,
    required this.serviceTitle,
    required this.onClose,
  });

  final Color textColor;
  final String serviceTitle;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final sub = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TweenAnimationBuilder<double>(
            duration: const Duration(milliseconds: 700),
            tween: Tween(begin: 0, end: 1),
            curve: Curves.elasticOut,
            builder: (_, v, __) => Transform.scale(
              scale: v,
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: BabifixDesign.cyan.withValues(alpha: 0.15),
                ),
                child: Icon(Icons.check_circle_rounded,
                    size: 60, color: BabifixDesign.cyan),
              ),
            ),
          ),
          const SizedBox(height: 28),
          Text(
            'Réservation envoyée !',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: textColor,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Votre demande pour « $serviceTitle » a été transmise. '
            'Le prestataire vous contactera pour confirmer le rendez-vous.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: sub,
              height: 1.5,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 40),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onClose,
              child: const Text('Retour à l\'accueil'),
            ),
          ),
        ],
      ),
    );
  }
}
