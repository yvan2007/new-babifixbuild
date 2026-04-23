import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:babifix_prestataire_flutter/babifix_api_config.dart';
import 'package:babifix_prestataire_flutter/shared/auth_utils.dart';

class PhotosInterventionService {
  static Future<Map<String, dynamic>?> uploadPhotos({
    required String reference,
    required List<String> photos,
    required String type,
  }) async {
    try {
      final token = await readStoredApiToken();
      if (token == null) return null;

      final response = await http.post(
        Uri.parse(
          '${babifixApiBaseUrl()}/api/prestataire/requests/$reference/photos',
        ),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'type': type,
          'photos_avant': type == 'avant' ? photos : [],
          'photos_apres': type == 'apres' ? photos : [],
        }),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      return null;
    }
  }
}
