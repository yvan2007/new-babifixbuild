import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import '../../babifix_api_config.dart';
import '../../babifix_design_system.dart';
import '../../shared/auth_utils.dart';
import '../../shared/widgets/babifix_ring_loader.dart';
import '../../shared/widgets/babifix_snackbar.dart';

class EditProfilePrestataireScreen extends StatefulWidget {
  final String? apiBase;
  final String? authToken;

  const EditProfilePrestataireScreen({super.key, this.apiBase, this.authToken});

  @override
  State<EditProfilePrestataireScreen> createState() =>
      _EditProfilePrestataireScreenState();
}

class _EditProfilePrestataireScreenState
    extends State<EditProfilePrestataireScreen> {
  final _nomCtrl = TextEditingController();
  final _specialiteCtrl = TextEditingController();
  final _villeCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  final _tarifCtrl = TextEditingController();
  final _expCtrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _success;
  String _statut = '';
  String _cniRectoUrl = '';
  String _cniVersoUrl = '';

  String get _base => widget.apiBase ?? babifixApiBaseUrl();

  Future<String?> _token() async {
    if (widget.authToken != null && widget.authToken!.isNotEmpty) return widget.authToken;
    return readStoredApiToken();
  }

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _nomCtrl.dispose();
    _specialiteCtrl.dispose();
    _villeCtrl.dispose();
    _bioCtrl.dispose();
    _tarifCtrl.dispose();
    _expCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final token = await _token();
    if (token == null) { setState(() => _loading = false); return; }
    try {
      final res = await http
          .get(Uri.parse('$_base/api/prestataire/profile'), headers: {'Authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final d = jsonDecode(res.body) as Map<String, dynamic>;
        _nomCtrl.text = d['nom'] as String? ?? '';
        _specialiteCtrl.text = d['specialite'] as String? ?? '';
        _villeCtrl.text = d['ville'] as String? ?? '';
        _bioCtrl.text = d['bio'] as String? ?? '';
        _tarifCtrl.text = d['tarif_horaire'] != null ? '${d['tarif_horaire']}' : '';
        _expCtrl.text = d['years_experience'] != null ? '${d['years_experience']}' : '0';
        setState(() {
          _statut = d['statut'] as String? ?? '';
          _cniRectoUrl = d['cni_recto_url'] as String? ?? '';
          _cniVersoUrl = d['cni_verso_url'] as String? ?? '';
          _loading = false;
        });
      } else { setState(() => _loading = false); }
    } catch (_) { setState(() => _loading = false); }
  }

  Future<void> _save() async {
    setState(() { _saving = true; _error = null; _success = null; });
    final token = await _token();
    if (token == null) return;
    final payload = <String, dynamic>{
      'nom': _nomCtrl.text.trim(), 'specialite': _specialiteCtrl.text.trim(),
      'ville': _villeCtrl.text.trim(), 'bio': _bioCtrl.text.trim(),
    };
    // tarif_horaire désactivé pour le prestataire — chaque devis a son prix.
    if (_expCtrl.text.trim().isNotEmpty) payload['years_experience'] = int.tryParse(_expCtrl.text.trim());
    try {
      final req = http.Request('PATCH', Uri.parse('$_base/api/prestataire/profile'));
      req.headers['Authorization'] = 'Bearer $token';
      req.headers['Content-Type'] = 'application/json';
      req.body = jsonEncode(payload);
      final streamedRes = await req.send().timeout(const Duration(seconds: 12));
      final body = await streamedRes.stream.bytesToString();
      if (streamedRes.statusCode == 200) {
        setState(() { _saving = false; _success = 'Profil mis a jour avec succes.'; });
      } else {
        setState(() { _saving = false; _error = (jsonDecode(body)['error'] ?? 'Erreur').toString(); });
      }
    } catch (_) { setState(() { _saving = false; _error = 'Erreur reseau.'; }); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BabifixDesign.navy,
      body: _loading
          ? const Center(child: BabifixRingLoader.cyan(size: 28))
          : CustomScrollView(slivers: [
              _buildAppBar(),
              SliverToBoxAdapter(child: _buildBody()),
            ]),
      bottomSheet: _buildSaveBar(),
    );
  }

  Widget _buildAppBar() {
    return SliverAppBar(
      expandedHeight: 180,
      floating: false,
      pinned: true,
      backgroundColor: BabifixDesign.navy,
      surfaceTintColor: Colors.transparent,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
        onPressed: () => Navigator.pop(context),
      ),
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [BabifixDesign.navy, Color(0xFF1A3A6E)],
            ),
          ),
          child: Stack(
            children: [
              Positioned(top: -40, right: -40, child: Container(
                width: 180, height: 180,
                decoration: BoxDecoration(shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [BabifixDesign.cyan.withValues(alpha: 0.12), Colors.transparent])),
              )),
              Positioned(top: -20, left: -20, child: Container(
                width: 100, height: 100,
                decoration: BoxDecoration(shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [BabifixDesign.ciOrange.withValues(alpha: 0.08), Colors.transparent])),
              )),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 60, 24, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Modifier mon profil',
                        style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.5)),
                    const SizedBox(height: 6),
                    Text(_nomCtrl.text.isNotEmpty ? _nomCtrl.text : 'Prestataire',
                        style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.6), fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            ],
          ),
        ),
        title: const Text('Modifier mon profil', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
      ),
    );
  }

  Widget _buildBody() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [Color(0xFF0B1B34), Color(0xFF081428)],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_statut.isNotEmpty) _StatutBadgePremium(statut: _statut),
          if (_success != null) _AlertPremium(message: _success!, color: BabifixDesign.success, icon: Icons.check_circle_rounded),
          if (_error != null) _AlertPremium(message: _error!, color: BabifixDesign.error, icon: Icons.error_rounded),
          const SizedBox(height: 16),

          // Informations personnelles
          _SectionCardPremium(
            icon: Icons.person_rounded,
            title: 'Informations personnelles',
            subtitle: 'Votre identite et localisation',
            color: BabifixDesign.cyan,
            child: Column(
              children: [
                _PremiumField(controller: _nomCtrl, label: 'Nom complet', icon: Icons.badge_rounded),
                const SizedBox(height: 12),
                _PremiumField(controller: _specialiteCtrl, label: 'Specialite', icon: Icons.work_rounded),
                const SizedBox(height: 12),
                _PremiumField(controller: _villeCtrl, label: 'Ville', icon: Icons.location_city_rounded),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // A propos
          _SectionCardPremium(
            icon: Icons.description_rounded,
            title: 'A propos de vous',
            subtitle: 'Decrirez votre experience',
            color: BabifixDesign.ciOrange,
            child: _PremiumTextField(
              controller: _bioCtrl,
              label: 'Biographie / Description',
              hint: 'Decrirez votre experience, vos competences...',
              maxLines: 4,
              maxLength: 500,
            ),
          ),
          const SizedBox(height: 16),

          // Expérience (le tarif horaire est supprimé : chaque devis a
          // son propre prix calculé sur place selon la prestation).
          _SectionCardPremium(
            icon: Icons.star_rounded,
            title: 'Expérience',
            subtitle: 'Vos années dans le métier',
            color: BabifixDesign.ciGreen,
            child: _PremiumField(
              controller: _expCtrl,
              label: "Années d'expérience",
              icon: Icons.star_rounded,
              keyboardType: TextInputType.number,
            ),
          ),
          const SizedBox(height: 16),

          // Documents d'identite
          _SectionCardPremium(
            icon: Icons.credit_card_rounded,
            title: 'Piece d\'identite',
            subtitle: 'CNI ou Passeport - Recto / Verso',
            color: const Color(0xFFA855F7),
            child: Row(
              children: [
                Expanded(child: _CniUploaderPremium(label: 'Recto', currentUrl: _cniRectoUrl,
                    uploadEndpoint: '$_base/api/prestataire/upload/cni-recto/', authToken: widget.authToken,
                    onUploaded: (url) => setState(() => _cniRectoUrl = url))),
                const SizedBox(width: 12),
                Expanded(child: _CniUploaderPremium(label: 'Verso', currentUrl: _cniVersoUrl,
                    uploadEndpoint: '$_base/api/prestataire/upload/cni-verso/', authToken: widget.authToken,
                    onUploaded: (url) => setState(() => _cniVersoUrl = url))),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Portfolio
          _SectionCardPremium(
            icon: Icons.photo_library_rounded,
            title: 'Galerie de realisations',
            subtitle: 'Photos de vos travaux',
            color: const Color(0xFF22C55E),
            child: _PortfolioEditorPremium(apiBase: _base, authToken: widget.authToken),
          ),
        ],
      ),
    );
  }

  Widget _buildSaveBar() {
    return Container(
      decoration: BoxDecoration(
        color: BabifixDesign.navy,
        border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewPaddingOf(context).bottom + 8,
        left: 16, right: 16, top: 12,
      ),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: FilledButton(
          onPressed: _saving ? null : _save,
          style: FilledButton.styleFrom(
            backgroundColor: _saving ? Colors.grey : BabifixDesign.cyan,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          child: _saving
              ? const SizedBox(width: 22, height: 22, child: BabifixRingLoader.cyan(size: 28))
              : const Text('Sauvegarder les modifications', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
        ),
      ),
    );
  }
}

// ─── Premium Section Card ─────────────────────────────────────────────────────

class _SectionCardPremium extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final Widget child;

  const _SectionCardPremium({
    required this.icon, required this.title, required this.subtitle,
    required this.color, required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [const Color(0xFF0F1D33), const Color(0xFF0B1525)],
        ),
        border: Border.all(color: color.withValues(alpha: 0.15)),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.06), blurRadius: 20, offset: const Offset(0, 8))],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(shape: BoxShape.circle,
                    gradient: LinearGradient(colors: [color.withValues(alpha: 0.2), color.withValues(alpha: 0.08)]),
                    border: Border.all(color: color.withValues(alpha: 0.3)),
                  ),
                  child: Icon(icon, color: color, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white)),
                    Text(subtitle, style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.45))),
                  ],
                )),
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

// ─── Premium Field ────────────────────────────────────────────────────────────

class _PremiumField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputType keyboardType;

  const _PremiumField({
    required this.controller, required this.label, required this.icon,
    this.keyboardType = TextInputType.text,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12),
        prefixIcon: Icon(icon, size: 18, color: BabifixDesign.cyan.withValues(alpha: 0.6)),
        filled: true,
        fillColor: const Color(0xFF0A1220),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: BabifixDesign.cyan, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }
}

// ─── Premium TextField (multi-line) ───────────────────────────────────────────

class _PremiumTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final int maxLines;
  final int? maxLength;

  const _PremiumTextField({
    required this.controller, required this.label, required this.hint,
    this.maxLines = 1, this.maxLength,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      maxLength: maxLength,
      style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12),
        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.25), fontSize: 12),
        filled: true,
        fillColor: const Color(0xFF0A1220),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: BabifixDesign.ciOrange, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        counterStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 11),
      ),
    );
  }
}

// ─── Statut Badge Premium ─────────────────────────────────────────────────────

class _StatutBadgePremium extends StatelessWidget {
  final String statut;
  const _StatutBadgePremium({required this.statut});

  @override
  Widget build(BuildContext context) {
    Color color; String label;
    switch (statut) {
      case 'Valide': color = BabifixDesign.success; label = 'Compte valide'; break;
      case 'En attente': color = BabifixDesign.warning; label = 'En attente de validation'; break;
      case 'Refuse': color = BabifixDesign.error; label = 'Dossier refuse'; break;
      default: color = Colors.grey; label = statut;
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(colors: [color.withValues(alpha: 0.15), color.withValues(alpha: 0.05)]),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.verified_rounded, color: color, size: 16),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
      ]),
    );
  }
}

// ─── Alert Premium ────────────────────────────────────────────────────────────

class _AlertPremium extends StatelessWidget {
  final String message;
  final Color color;
  final IconData icon;
  const _AlertPremium({required this.message, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(colors: [color.withValues(alpha: 0.1), color.withValues(alpha: 0.03)]),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 10),
        Expanded(child: Text(message, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600))),
      ]),
    );
  }
}

// ─── CNI Uploader Premium ─────────────────────────────────────────────────────

class _CniUploaderPremium extends StatefulWidget {
  final String label;
  final String currentUrl;
  final String uploadEndpoint;
  final String? authToken;
  final void Function(String url) onUploaded;

  const _CniUploaderPremium({
    required this.label, required this.currentUrl,
    required this.uploadEndpoint, required this.onUploaded, this.authToken,
  });

  @override
  State<_CniUploaderPremium> createState() => _CniUploaderPremiumState();
}

class _CniUploaderPremiumState extends State<_CniUploaderPremium> {
  bool _uploading = false;
  late String _url;

  @override
  void initState() { super.initState(); _url = widget.currentUrl; }

  Future<String?> _token() async {
    if (widget.authToken != null && widget.authToken!.isNotEmpty) return widget.authToken;
    return readStoredApiToken();
  }

  Future<void> _pick() async {
    final picker = ImagePicker();
    final xfile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80, maxWidth: 1800);
    if (xfile == null) return;
    setState(() => _uploading = true);
    final token = await _token();
    try {
      final req = http.MultipartRequest('POST', Uri.parse(widget.uploadEndpoint));
      req.headers['Authorization'] = 'Bearer $token';
      req.files.add(await http.MultipartFile.fromPath('file', xfile.path));
      final streamed = await req.send().timeout(const Duration(seconds: 30));
      final body = await streamed.stream.bytesToString();
      if (streamed.statusCode == 200) {
        final data = jsonDecode(body) as Map<String, dynamic>;
        final url = data['url'] as String? ?? '';
        setState(() => _url = url);
        widget.onUploaded(url);
        if (mounted) showBabifixToast(
        context,
        type: BabifixToastType.info,
        message: '${widget.label} uploade',
      );
      } else {
        final err = (jsonDecode(body) as Map<String, dynamic>)['error'] ?? 'Erreur upload';
        if (mounted) showBabifixToast(
        context,
        type: BabifixToastType.info,
        message: err.toString(),
      );
      }
    } catch (_) {
      if (mounted) showBabifixToast(
        context,
        type: BabifixToastType.error,
        message: 'Erreur reseau',
      );
    } finally { if (mounted) setState(() => _uploading = false); }
  }

  @override
  Widget build(BuildContext context) {
    final hasDoc = _url.isNotEmpty;
    return GestureDetector(
      onTap: _uploading ? null : _pick,
      child: Container(
        height: 120,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: hasDoc
              ? LinearGradient(colors: [const Color(0xFF1A3A6E).withValues(alpha: 0.3), const Color(0xFF0B1B34).withValues(alpha: 0.2)])
              : LinearGradient(colors: [const Color(0xFF0A1220), const Color(0xFF081018)]),
          border: Border.all(
            color: hasDoc ? BabifixDesign.ciOrange.withValues(alpha: 0.4) : Colors.white.withValues(alpha: 0.08),
            width: hasDoc ? 1.5 : 1,
          ),
        ),
        child: _uploading
            ? const Center(child: BabifixRingLoader.cyan(size: 28))
            : hasDoc
                ? Stack(children: [
                    ClipRRect(borderRadius: BorderRadius.circular(15), child: Image.network(_url,
                        width: double.infinity, height: double.infinity, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image_rounded, color: Colors.grey)))),
                    Positioned(bottom: 0, left: 0, right: 0, child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
                        gradient: LinearGradient(colors: [Colors.transparent, Colors.black.withValues(alpha: 0.7)]),
                      ),
                      child: Text(widget.label, textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                    )),
                    Positioned(top: 8, right: 8, child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(color: BabifixDesign.cyan, borderRadius: BorderRadius.circular(8)),
                      child: const Icon(Icons.edit_rounded, color: Colors.white, size: 13),
                    )),
                  ])
                : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(shape: BoxShape.circle,
                        gradient: LinearGradient(colors: [BabifixDesign.cyan.withValues(alpha: 0.15), BabifixDesign.cyan.withValues(alpha: 0.05)]),
                      ),
                      child: const Icon(Icons.credit_card_rounded, color: BabifixDesign.cyan, size: 20),
                    ),
                    const SizedBox(height: 8),
                    Text(widget.label, textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 3),
                    Text('Appuyer pour ajouter',
                        style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: 0.35))),
                  ]),
      ),
    );
  }
}

// ─── Portfolio Editor Premium ─────────────────────────────────────────────────

class _PortfolioEditorPremium extends StatefulWidget {
  final String apiBase;
  final String? authToken;
  const _PortfolioEditorPremium({required this.apiBase, this.authToken});

  @override
  State<_PortfolioEditorPremium> createState() => _PortfolioEditorPremiumState();
}

class _PortfolioEditorPremiumState extends State<_PortfolioEditorPremium> {
  List<Map<String, dynamic>> _photos = [];
  bool _loading = true;
  bool _uploading = false;

  @override
  void initState() { super.initState(); _load(); }

  Future<String?> _token() async {
    if (widget.authToken != null && widget.authToken!.isNotEmpty) return widget.authToken;
    return readStoredApiToken();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final token = await _token();
    if (token == null) { setState(() => _loading = false); return; }
    try {
      final res = await http.get(Uri.parse('${widget.apiBase}/api/prestataire/portfolio'),
          headers: {'Authorization': 'Bearer $token'}).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        setState(() { _photos = ((data['photos'] as List?) ?? []).cast<Map<String, dynamic>>().toList(); _loading = false; });
      } else { setState(() => _loading = false); }
    } catch (_) { setState(() => _loading = false); }
  }

  Widget _buildPhoto(String src, double size) {
    final ph = Container(width: size, height: size, color: const Color(0xFF0A1220),
        child: const Icon(Icons.photo_outlined, color: Colors.grey, size: 24));
    if (src.isEmpty) return ph;
    if (src.startsWith('data:image/')) {
      try { final bytes = base64Decode(src.split(',').last); return Image.memory(bytes, width: size, height: size, fit: BoxFit.cover, errorBuilder: (_, __, ___) => ph); }
      catch (_) { return ph; }
    }
    if (src.startsWith('http://') || src.startsWith('https://')) return Image.network(src, width: size, height: size, fit: BoxFit.cover, errorBuilder: (_, __, ___) => ph);
    try { final f = File(src); if (f.existsSync()) return Image.file(f, width: size, height: size, fit: BoxFit.cover, errorBuilder: (_, __, ___) => ph); } catch (_) {}
    return ph;
  }

  Future<void> _addPhoto() async {
    final picker = ImagePicker();
    final xfile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 60, maxWidth: 1024);
    if (xfile == null) return;
    final bytes = await xfile.readAsBytes();
    final ext = xfile.path.split('.').last.toLowerCase();
    final mime = ext == 'png' ? 'image/png' : 'image/jpeg';
    final b64 = 'data:$mime;base64,${base64Encode(bytes)}';
    setState(() => _uploading = true);
    final token = await _token();
    try {
      final res = await http.post(Uri.parse('${widget.apiBase}/api/prestataire/portfolio'),
          headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
          body: jsonEncode({'photo': b64, 'caption': ''}));
      if (res.statusCode == 200) { _load(); }
      else {
        final err = jsonDecode(res.body)['error'] ?? 'Erreur';
        if (mounted) showBabifixToast(
        context,
        type: BabifixToastType.error,
        message: 'Impossible d\'ajouter : $err',
      );
      }
    } catch (_) {
      if (mounted) showBabifixToast(
        context,
        type: BabifixToastType.error,
        message: 'Erreur reseau',
      );
    }
    setState(() => _uploading = false);
  }

  Future<void> _deletePhoto(int idx) async {
    final token = await _token();
    try {
      final req = http.Request('DELETE', Uri.parse('${widget.apiBase}/api/prestataire/portfolio/$idx'));
      req.headers['Authorization'] = 'Bearer $token';
      final streamedRes = await req.send().timeout(const Duration(seconds: 10));
      if (streamedRes.statusCode == 200) _load();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: BabifixRingLoader.cyan(size: 28));
    return Wrap(spacing: 10, runSpacing: 10, children: [
      ..._photos.asMap().entries.map((entry) {
        final i = entry.key;
        final src = entry.value['photo'] as String? ?? '';
        return Stack(children: [
          ClipRRect(borderRadius: BorderRadius.circular(12), child: _buildPhoto(src, 85)),
          Positioned(top: 4, right: 4, child: GestureDetector(onTap: () => _deletePhoto(i),
              child: Container(width: 22, height: 22, decoration: const BoxDecoration(color: BabifixDesign.error, shape: BoxShape.circle),
                  child: const Icon(Icons.close_rounded, size: 12, color: Colors.white)))),
        ]);
      }),
      if (_photos.length < 12)
        GestureDetector(onTap: _uploading ? null : _addPhoto,
            child: Container(width: 85, height: 85,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: LinearGradient(colors: [const Color(0xFF0A1220), const Color(0xFF081018)]),
                  border: Border.all(color: BabifixDesign.cyan.withValues(alpha: 0.2), style: BorderStyle.solid, width: 1.5),
                ),
                child: _uploading
                    ? const Center(child: BabifixRingLoader.cyan(size: 28))
                    : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Container(width: 32, height: 32, decoration: BoxDecoration(shape: BoxShape.circle,
                            gradient: LinearGradient(colors: [BabifixDesign.cyan.withValues(alpha: 0.15), BabifixDesign.cyan.withValues(alpha: 0.05)])),
                            child: const Icon(Icons.add_photo_alternate_rounded, color: BabifixDesign.cyan, size: 18)),
                        const SizedBox(height: 4),
                        const Text('Ajouter', style: TextStyle(fontSize: 10, color: BabifixDesign.cyan, fontWeight: FontWeight.w600)),
                      ]))),
    ]);
  }
}
