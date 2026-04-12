import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import '../../babifix_api_config.dart';
import '../../babifix_design_system.dart';
import '../../shared/auth_utils.dart';

/// Écran de modification du profil prestataire.
/// Accessible depuis le profil via un bouton "Modifier".
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
    if (widget.authToken != null && widget.authToken!.isNotEmpty) {
      return widget.authToken;
    }
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
    if (token == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final res = await http
          .get(
            Uri.parse('$_base/api/prestataire/profile'),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final d = jsonDecode(res.body) as Map<String, dynamic>;
        _nomCtrl.text = d['nom'] as String? ?? '';
        _specialiteCtrl.text = d['specialite'] as String? ?? '';
        _villeCtrl.text = d['ville'] as String? ?? '';
        _bioCtrl.text = d['bio'] as String? ?? '';
        _tarifCtrl.text = d['tarif_horaire'] != null
            ? '${d['tarif_horaire']}'
            : '';
        _expCtrl.text = d['years_experience'] != null
            ? '${d['years_experience']}'
            : '0';
        setState(() {
          _statut = d['statut'] as String? ?? '';
          _cniRectoUrl = d['cni_recto_url'] as String? ?? '';
          _cniVersoUrl = d['cni_verso_url'] as String? ?? '';
          _loading = false;
        });
      } else {
        setState(() => _loading = false);
      }
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
      _success = null;
    });
    final token = await _token();
    if (token == null) return;
    final payload = <String, dynamic>{
      'nom': _nomCtrl.text.trim(),
      'specialite': _specialiteCtrl.text.trim(),
      'ville': _villeCtrl.text.trim(),
      'bio': _bioCtrl.text.trim(),
    };
    if (_tarifCtrl.text.trim().isNotEmpty) {
      payload['tarif_horaire'] = double.tryParse(_tarifCtrl.text.trim());
    }
    if (_expCtrl.text.trim().isNotEmpty) {
      payload['years_experience'] = int.tryParse(_expCtrl.text.trim());
    }
    try {
      final req = http.Request(
        'PATCH',
        Uri.parse('$_base/api/prestataire/profile'),
      );
      req.headers['Authorization'] = 'Bearer $token';
      req.headers['Content-Type'] = 'application/json';
      req.body = jsonEncode(payload);
      final streamedRes = await req.send().timeout(const Duration(seconds: 12));
      final body = await streamedRes.stream.bytesToString();
      if (streamedRes.statusCode == 200) {
        setState(() {
          _saving = false;
          _success = 'Profil mis à jour avec succès.';
        });
      } else {
        final err = jsonDecode(body)['error'] ?? 'Erreur';
        setState(() {
          _saving = false;
          _error = err.toString();
        });
      }
    } catch (_) {
      setState(() {
        _saving = false;
        _error = 'Erreur réseau.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('Modifier mon profil'),
        backgroundColor: cs.surface,
        surfaceTintColor: Colors.transparent,
        actions: [
          if (!_loading)
            TextButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text(
                      'Sauvegarder',
                      style: TextStyle(
                        color: BabifixDesign.ciOrange,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_statut.isNotEmpty) _StatutBadge(statut: _statut),
                  if (_success != null)
                    _AlertBanner(
                      message: _success!,
                      color: BabifixDesign.success,
                      icon: Icons.check_circle_rounded,
                    ),
                  if (_error != null)
                    _AlertBanner(
                      message: _error!,
                      color: BabifixDesign.error,
                      icon: Icons.error_rounded,
                    ),
                  const SizedBox(height: 16),
                  // ── Champs ──────────────────────────────────────────────
                  _SectionTitle('Informations personnelles'),
                  const SizedBox(height: 12),
                  _Field(
                    controller: _nomCtrl,
                    label: 'Nom complet',
                    icon: Icons.person_rounded,
                  ),
                  _Field(
                    controller: _specialiteCtrl,
                    label: 'Spécialité',
                    icon: Icons.work_rounded,
                  ),
                  _Field(
                    controller: _villeCtrl,
                    label: 'Ville',
                    icon: Icons.location_city_rounded,
                  ),
                  const SizedBox(height: 20),
                  _SectionTitle('À propos de vous'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _bioCtrl,
                    maxLines: 4,
                    maxLength: 500,
                    decoration: InputDecoration(
                      labelText: 'Biographie / Description',
                      hintText: 'Décrivez votre expérience, vos compétences…',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(
                          BabifixDesign.radiusMD,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(
                          BabifixDesign.radiusMD,
                        ),
                        borderSide: const BorderSide(
                          color: BabifixDesign.ciOrange,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _SectionTitle('Tarifs & Expérience'),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _Field(
                          controller: _tarifCtrl,
                          label: 'Tarif horaire (FCFA)',
                          icon: Icons.payments_rounded,
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _Field(
                          controller: _expCtrl,
                          label: 'Années d\'exp.',
                          icon: Icons.star_rounded,
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  // ── Documents d'identité (CNI) ───────────────────────────
                  _SectionTitle('Pièce d\'identité (CNI / Passeport)'),
                  const SizedBox(height: 8),
                  const Text(
                    'Uploadez le recto et le verso de votre CNI ou passeport. Ces documents sont vérifiés par l\'administration.',
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _CniUploader(
                          label: 'Recto (face avant)',
                          currentUrl: _cniRectoUrl,
                          uploadEndpoint: '$_base/api/prestataire/upload/cni-recto/',
                          authToken: widget.authToken,
                          onUploaded: (url) => setState(() => _cniRectoUrl = url),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _CniUploader(
                          label: 'Verso (face arrière)',
                          currentUrl: _cniVersoUrl,
                          uploadEndpoint: '$_base/api/prestataire/upload/cni-verso/',
                          authToken: widget.authToken,
                          onUploaded: (url) => setState(() => _cniVersoUrl = url),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  // ── Portfolio ────────────────────────────────────────────
                  _SectionTitle('Galerie de réalisations'),
                  const SizedBox(height: 8),
                  const Text(
                    'Ajoutez des photos de vos travaux pour attirer plus de clients.',
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  _PortfolioEditor(apiBase: _base, authToken: widget.authToken),
                  const SizedBox(height: 40),
                ],
              ),
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Widget galerie portfolio
// ─────────────────────────────────────────────────────────────────────────────
class _PortfolioEditor extends StatefulWidget {
  final String apiBase;
  final String? authToken;

  const _PortfolioEditor({required this.apiBase, this.authToken});

  @override
  State<_PortfolioEditor> createState() => _PortfolioEditorState();
}

class _PortfolioEditorState extends State<_PortfolioEditor> {
  List<Map<String, dynamic>> _photos = [];
  bool _loading = true;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<String?> _token() async {
    if (widget.authToken != null && widget.authToken!.isNotEmpty) {
      return widget.authToken;
    }
    return readStoredApiToken();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final token = await _token();
    if (token == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final res = await http
          .get(
            Uri.parse('${widget.apiBase}/api/prestataire/portfolio'),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        setState(() {
          _photos = ((data['photos'] as List?) ?? [])
              .cast<Map<String, dynamic>>()
              .toList();
          _loading = false;
        });
      } else {
        setState(() => _loading = false);
      }
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  /// Affiche une photo portfolio quel que soit son format (base64, HTTP, fichier).
  Widget _buildPortfolioPhoto(String src, double size) {
    final ph = Container(
      width: size, height: size,
      color: Colors.grey.shade200,
      child: const Icon(Icons.photo_outlined, color: Colors.grey),
    );
    if (src.isEmpty) return ph;

    if (src.startsWith('data:image/')) {
      try {
        final bytes = base64Decode(src.split(',').last);
        return Image.memory(bytes, width: size, height: size, fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => ph);
      } catch (_) { return ph; }
    }

    if (src.startsWith('http://') || src.startsWith('https://')) {
      return Image.network(src, width: size, height: size, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => ph);
    }

    try {
      final f = File(src);
      if (f.existsSync()) {
        return Image.file(f, width: size, height: size, fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => ph);
      }
    } catch (_) {}
    return ph;
  }

  Future<void> _addPhoto() async {
    final picker = ImagePicker();
    final xfile = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 60,
      maxWidth: 1024,
    );
    if (xfile == null) return;
    final bytes = await xfile.readAsBytes();
    final ext = xfile.path.split('.').last.toLowerCase();
    final mime = ext == 'png' ? 'image/png' : 'image/jpeg';
    final b64 = 'data:$mime;base64,${base64Encode(bytes)}';

    setState(() => _uploading = true);
    final token = await _token();
    try {
      final res = await http.post(
        Uri.parse('${widget.apiBase}/api/prestataire/portfolio'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'photo': b64, 'caption': ''}),
      );
      if (res.statusCode == 200) {
        _load();
      } else {
        final err = jsonDecode(res.body)['error'] ?? 'Erreur';
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Impossible d\'ajouter : $err')),
          );
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Erreur réseau.')));
      }
    }
    setState(() => _uploading = false);
  }

  Future<void> _deletePhoto(int idx) async {
    final token = await _token();
    try {
      final req = http.Request(
        'DELETE',
        Uri.parse('${widget.apiBase}/api/prestataire/portfolio/$idx'),
      );
      req.headers['Authorization'] = 'Bearer $token!';
      final streamedRes = await req.send().timeout(const Duration(seconds: 10));
      if (streamedRes.statusCode == 200) {
        _load();
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        ..._photos.asMap().entries.map((entry) {
          final i = entry.key;
          final photo = entry.value;
          final src = photo['photo'] as String? ?? '';
          return Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(BabifixDesign.radiusMD),
                child: _buildPortfolioPhoto(src, 90),
              ),
              Positioned(
                top: 4,
                right: 4,
                child: GestureDetector(
                  onTap: () => _deletePhoto(i),
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: const BoxDecoration(
                      color: BabifixDesign.error,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      size: 14,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          );
        }),
        if (_photos.length < 12)
          GestureDetector(
            onTap: _uploading ? null : _addPhoto,
            child: Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(BabifixDesign.radiusMD),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: _uploading
                  ? const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.add_photo_alternate_rounded,
                          color: Colors.grey,
                          size: 28,
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Ajouter',
                          style: TextStyle(fontSize: 10, color: Colors.grey),
                        ),
                      ],
                    ),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sous-composants locaux
// ─────────────────────────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
  );
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputType keyboardType;

  const _Field({
    required this.controller,
    required this.label,
    required this.icon,
    this.keyboardType = TextInputType.text,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(BabifixDesign.radiusMD),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(BabifixDesign.radiusMD),
          borderSide: const BorderSide(color: BabifixDesign.ciOrange, width: 2),
        ),
      ),
    ),
  );
}

class _StatutBadge extends StatelessWidget {
  final String statut;
  const _StatutBadge({required this.statut});

  @override
  Widget build(BuildContext context) {
    Color color;
    String label;
    switch (statut) {
      case 'Valide':
        color = BabifixDesign.success;
        label = 'Compte validé';
        break;
      case 'En attente':
        color = BabifixDesign.warning;
        label = 'En attente de validation';
        break;
      case 'Refuse':
        color = BabifixDesign.error;
        label = 'Dossier refusé';
        break;
      default:
        color = Colors.grey;
        label = statut;
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(BabifixDesign.radiusMD),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.info_rounded, color: color, size: 16),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _AlertBanner extends StatelessWidget {
  final String message;
  final Color color;
  final IconData icon;

  const _AlertBanner({
    required this.message,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(BabifixDesign.radiusMD),
      border: Border.all(color: color.withValues(alpha: 0.25)),
    ),
    child: Row(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Widget upload CNI recto / verso
// ─────────────────────────────────────────────────────────────────────────────
class _CniUploader extends StatefulWidget {
  final String label;
  final String currentUrl;
  final String uploadEndpoint;
  final String? authToken;
  final void Function(String url) onUploaded;

  const _CniUploader({
    required this.label,
    required this.currentUrl,
    required this.uploadEndpoint,
    required this.onUploaded,
    this.authToken,
  });

  @override
  State<_CniUploader> createState() => _CniUploaderState();
}

class _CniUploaderState extends State<_CniUploader> {
  bool _uploading = false;
  late String _url;

  @override
  void initState() {
    super.initState();
    _url = widget.currentUrl;
  }

  Future<String?> _token() async {
    if (widget.authToken != null && widget.authToken!.isNotEmpty) {
      return widget.authToken;
    }
    return readStoredApiToken();
  }

  Future<void> _pick() async {
    final picker = ImagePicker();
    final xfile = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 1800,
    );
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
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${widget.label} uploadé ✓')),
          );
        }
      } else {
        final err = (jsonDecode(body) as Map<String, dynamic>)['error'] ?? 'Erreur upload';
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(err.toString())),
          );
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erreur réseau lors de l\'upload.')),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasDoc = _url.isNotEmpty;
    return GestureDetector(
      onTap: _uploading ? null : _pick,
      child: Container(
        height: 110,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: hasDoc
                ? BabifixDesign.ciOrange.withValues(alpha: 0.5)
                : Colors.grey.shade300,
            width: hasDoc ? 2 : 1.5,
            style: hasDoc ? BorderStyle.solid : BorderStyle.solid,
          ),
          color: hasDoc
              ? BabifixDesign.ciOrange.withValues(alpha: 0.04)
              : Colors.grey.shade50,
        ),
        child: _uploading
            ? const Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: BabifixDesign.ciOrange,
                ),
              )
            : hasDoc
                ? Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(13),
                        child: Image.network(
                          _url,
                          width: double.infinity,
                          height: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Center(
                            child: Icon(Icons.broken_image_rounded, color: Colors.grey),
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          decoration: BoxDecoration(
                            borderRadius: const BorderRadius.vertical(
                                bottom: Radius.circular(12)),
                            color: Colors.black.withValues(alpha: 0.55),
                          ),
                          child: Text(
                            widget.label,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: BabifixDesign.ciOrange,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Icon(
                            Icons.edit_rounded,
                            color: Colors.white,
                            size: 12,
                          ),
                        ),
                      ),
                    ],
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.credit_card_rounded,
                        color: Colors.grey.shade400,
                        size: 32,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        widget.label,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade500,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Appuyer pour ajouter',
                        style: TextStyle(fontSize: 10, color: Colors.grey.shade400),
                      ),
                    ],
                  ),
      ),
    );
  }
}
