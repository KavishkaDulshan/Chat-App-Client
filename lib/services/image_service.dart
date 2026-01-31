import 'dart:typed_data'; // Needed for bytes
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart'; // Needed for kIsWeb
import 'package:image_picker/image_picker.dart'; // Uses XFile
import '../config.dart';

class ImageService {
  String get uploadUrl => '${AppConfig.baseUrl}/upload';

  final Dio _dio = Dio();
  final ImagePicker _picker = ImagePicker();

  // ✅ FIXED: Return XFile? instead of File?
  Future<XFile?> pickImage() async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 70,
        maxWidth: 1080,
      );
      return pickedFile;
    } catch (e) {
      print("Pick Error: $e");
    }
    return null;
  }

  // ✅ FIXED: Accept XFile instead of File
  Future<String?> uploadImage(XFile file) async {
    try {
      FormData formData;

      if (kIsWeb) {
        // 🌐 WEB: Read bytes directly
        Uint8List bytes = await file.readAsBytes();
        formData = FormData.fromMap({
          "image": MultipartFile.fromBytes(bytes, filename: file.name),
        });
      } else {
        // 📱 MOBILE/DESKTOP: Use file path
        formData = FormData.fromMap({
          "image": await MultipartFile.fromFile(file.path, filename: file.name),
        });
      }

      Response response = await _dio.post(uploadUrl, data: formData);

      if (response.statusCode == 200) {
        return response.data['url'];
      }
    } catch (e) {
      print("Upload Error: $e");
    }
    return null;
  }
}
