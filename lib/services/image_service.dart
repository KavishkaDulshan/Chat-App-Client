import 'dart:io'; // <--- Import Platform
import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';
import '../config.dart';

class ImageService {
  // DYNAMIC URL
  String get uploadUrl => '${AppConfig.baseUrl}/upload';

  final Dio _dio = Dio();
  final ImagePicker _picker = ImagePicker();

  Future<File?> pickImage() async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 70,
        maxWidth: 1080,
      );
      if (pickedFile != null) return File(pickedFile.path);
    } catch (e) {
      print("Pick Error: $e");
    }
    return null;
  }

  Future<String?> uploadImage(File file) async {
    try {
      String fileName = file.path.split('/').last;
      FormData formData = FormData.fromMap({
        "image": await MultipartFile.fromFile(file.path, filename: fileName),
      });

      // Use the dynamic getter 'uploadUrl'
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
