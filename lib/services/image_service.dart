// Needed for bytes
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart'; // Needed for kIsWeb
import 'package:image_picker/image_picker.dart'; // Uses XFile
import '../config.dart';

class ImageService {
  String get uploadUrl => '${AppConfig.baseUrl}/upload';
  String get profileUploadUrl => '${AppConfig.baseUrl}/upload/profile';

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

  // ✅ General image upload (chat images)
  Future<String?> uploadImage(XFile file) async {
    return _upload(file, uploadUrl);
  }

  // ✅ Profile picture upload (uses dedicated endpoint for 256px compression)
  Future<String?> uploadProfileImage(XFile file) async {
    return _upload(file, profileUploadUrl);
  }

  // Shared upload logic
  Future<String?> _upload(XFile file, String url) async {
    try {
      FormData formData;

      if (kIsWeb) {
        Uint8List bytes = await file.readAsBytes();
        formData = FormData.fromMap({
          "file": MultipartFile.fromBytes(
            bytes,
            filename: file.name,
          ),
        });
      } else {
        formData = FormData.fromMap({
          "file": await MultipartFile.fromFile(
            file.path,
            filename: file.name,
          ),
        });
      }
      Response response = await _dio.post(url, data: formData);

      if (response.statusCode == 200) {
        return response.data['url'];
      }
    } catch (e) {
      print("Upload Error: $e");
    }
    return null;
  }
}
