import 'dart:io';
import 'package:http/http.dart' as http;

class VisionApiClient {
  final String baseUrl;
  final String authToken;

  VisionApiClient({
    required this.baseUrl,
    required this.authToken,
  });

  /// Upload images for pantry vision analysis
  Future<Map<String, dynamic>> analyzePantry(
    List<File> images, {
    required String userId,
  }) async {
    return _uploadAndAnalyze(
      images: images,
      endpoint: '/vision/grocery/pantry-scan',
      userId: userId,
      domain: 'grocery_shopping',
    );
  }

  /// Upload images for shelf/substitution analysis
  Future<Map<String, dynamic>> analyzeShelf(
    File image, {
    required String userId,
    required String originalItem,
    required Map<String, dynamic> userPreferences,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/vision/grocery/shelf-analysis'),
    )
      ..headers['Authorization'] = 'Bearer $authToken'
      ..fields['original_item'] = originalItem
      ..fields['user_preferences'] = _jsonEncode(userPreferences)
      ..files.add(
        await http.MultipartFile.fromPath('file', image.path),
      );

    final response = await request.send();
    return _handleResponse(response, 'analyzeShelf');
  }

  /// Upload receipt image for splitting
  Future<Map<String, dynamic>> analyzeReceipt(
    File image, {
    required String userId,
    required String tripId,
    required List<Map<String, dynamic>> mergedList,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/vision/grocery/receipt-analysis'),
    )
      ..headers['Authorization'] = 'Bearer $authToken'
      ..fields['trip_id'] = tripId
      ..fields['merged_list'] = _jsonEncode(mergedList)
      ..files.add(
        await http.MultipartFile.fromPath('file', image.path),
      );

    final response = await request.send();
    return _handleResponse(response, 'analyzeReceipt');
  }

  /// Upload images for home repair damage detection
  Future<Map<String, dynamic>> analyzeDamage(
    List<File> images, {
    required String userId,
    String? roomOrArea,
  }) async {
    return _uploadAndAnalyze(
      images: images,
      endpoint: '/vision/home-repair/damage-detection',
      userId: userId,
      domain: 'home_repair',
      additionalFields: {
        if (roomOrArea != null) 'room_or_area': roomOrArea,
      },
    );
  }

  /// Upload images for yard maintenance scanning
  Future<Map<String, dynamic>> analyzeYardMaintenance(
    List<File> images, {
    required String userId,
  }) async {
    return _uploadAndAnalyze(
      images: images,
      endpoint: '/vision/yard/maintenance-scan',
      userId: userId,
      domain: 'yard_work',
    );
  }

  /// Upload images for pet assessment
  Future<Map<String, dynamic>> assessPet(
    List<File> images, {
    required String userId,
    required Map<String, dynamic> petInfo,
  }) async {
    return _uploadAndAnalyze(
      images: images,
      endpoint: '/vision/pet-sitting/assessment',
      userId: userId,
      domain: 'pet_sitting',
      additionalFields: {
        'pet_info': _jsonEncode(petInfo),
      },
    );
  }

  /// Upload images for cleaning/organizing analysis
  Future<Map<String, dynamic>> analyzeCleaningNeeds(
    List<File> images, {
    required String userId,
    String? roomType,
  }) async {
    return _uploadAndAnalyze(
      images: images,
      endpoint: '/vision/cleaning/needs-analysis',
      userId: userId,
      domain: 'cleaning',
      additionalFields: {
        if (roomType != null) 'room_type': roomType,
      },
    );
  }

  /// Generic multipart upload and analysis
  Future<Map<String, dynamic>> _uploadAndAnalyze({
    required List<File> images,
    required String endpoint,
    required String userId,
    required String domain,
    Map<String, String>? additionalFields,
  }) async {
    final request = http.MultipartRequest('POST', Uri.parse('$baseUrl$endpoint'))
      ..headers['Authorization'] = 'Bearer $authToken';

    // Add files
    for (final image in images) {
      request.files.add(
        await http.MultipartFile.fromPath('files', image.path),
      );
    }

    // Add standard fields
    request.fields['user_id'] = userId;

    // Add any additional fields
    additionalFields?.forEach((key, value) {
      request.fields[key] = value;
    });

    final response = await request.send();
    return _handleResponse(response, endpoint);
  }

  /// Handle HTTP response
  Future<Map<String, dynamic>> _handleResponse(
    http.StreamedResponse response,
    String operation,
  ) async {
    final responseBody = await response.stream.bytesToString();

    if (response.statusCode == 200 || response.statusCode == 201) {
      return _parseJson(responseBody);
    } else if (response.statusCode == 401) {
      throw UnauthorizedException('Unauthorized: Invalid or expired token');
    } else if (response.statusCode == 400) {
      throw BadRequestException('Bad request: ${_parseJson(responseBody)['error'] ?? 'Unknown error'}');
    } else {
      throw ApiException(
        'Failed to complete $operation: ${response.statusCode} - $responseBody',
      );
    }
  }

  /// Safely parse JSON
  Map<String, dynamic> _parseJson(String body) {
    try {
      return Map<String, dynamic>.from(
        (Uri.parse('data:application/json,$body').data) as Map<String, dynamic>,
      );
    } catch (e) {
      try {
        return {'raw_response': body};
      } catch (_) {
        return {'error': 'Failed to parse response'};
      }
    }
  }

  /// JSON encode helper
  String _jsonEncode(dynamic data) {
    return data.toString(); // Use simple toString for form field
  }
}

class ApiException implements Exception {
  ApiException(this.message);
  final String message;

  @override
  String toString() => message;
}

class UnauthorizedException extends ApiException {
  UnauthorizedException(super.message);
}

class BadRequestException extends ApiException {
  BadRequestException(super.message);
}
