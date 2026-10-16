import 'package:attendance_app/utils/face_detection/google_ml_kit.dart';
import 'package:camera/camera.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:dotted_border/dotted_border.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:lottie/lottie.dart';
import 'package:attendance_app/ui/home_screen.dart';

class AttendScreen extends StatefulWidget {
  const AttendScreen({super.key});

  @override
  State<AttendScreen> createState() => _AttendScreenState();
}

class _AttendScreenState extends State<AttendScreen> {
  CameraController? _controller;
  late final FaceDetector _faceDetector;
  String? _errorMessage;
  String? _locationAddress;
  String _status = 'Leave';
  double? _latitude;
  double? _longitude;
  bool _isBusy = false;
  bool _isLoadingLocation = false;
  bool _hasFace = false;

  bool get _isCameraReady =>
      _controller != null && _controller!.value.isInitialized;

  @override
  void initState() {
    super.initState();
    _faceDetector = GoogleMLKit.vision.faceDetector();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw CameraException(
          'NoCameraAvailable',
          'No camera is available on this device.',
        );
      }

      final frontCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        frontCamera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await controller.initialize();

      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _controller = controller;
      });
    } on CameraException catch (error) {
      _setError(error.description ?? error.code);
    } catch (error) {
      _setError(error.toString());
    }
  }

  void _setError(String message) {
    if (!mounted) {
      return;
    }

    setState(() {
      _errorMessage = message;
    });
  }

  Future<bool> _handleLocationPermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _showMessage(
        'Layanan GPS tidak aktif. Silakan aktifkan GPS perangkat Anda.',
        Colors.orange,
      );
      return false;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        _showMessage('Izin akses lokasi ditolak.', Colors.orange);
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      _showMessage(
        'Izin lokasi ditolak permanen. Buka pengaturan aplikasi untuk mengizinkan.',
        Colors.redAccent,
      );
      return false;
    }

    return true;
  }

  Future<bool> _getGeoLocation() async {
    final hasPermission = await _handleLocationPermission();
    if (!hasPermission) {
      return false;
    }

    if (mounted) {
      setState(() {
        _isLoadingLocation = true;
      });
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      final address = await _getAddressFromLongLat(position);

      if (!mounted) {
        return false;
      }

      setState(() {
        _latitude = position.latitude;
        _longitude = position.longitude;
        _locationAddress = address;
      });
      return true;
    } catch (error) {
      if (mounted) {
        _showMessage('Gagal mengambil lokasi: $error', Colors.redAccent);
      }
      return false;
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingLocation = false;
        });
      }
    }
  }

  Future<String> _getAddressFromLongLat(Position position) async {
    try {
      final placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
      if (placemarks.isEmpty) {
        return _formatCoordinates(position);
      }

      final place = placemarks.first;
      final parts = <String?>[
        place.street,
        place.subLocality,
        place.locality,
        place.country,
      ];
      final address = parts
          .whereType<String>()
          .map((part) => part.trim())
          .where((part) => part.isNotEmpty)
          .join(', ');
      return address.isEmpty ? _formatCoordinates(position) : address;
    } catch (_) {
      return _formatCoordinates(position);
    }
  }

  String _formatCoordinates(Position position) {
    return 'Lat: ${position.latitude.toStringAsFixed(6)}, '
        'Long: ${position.longitude.toStringAsFixed(6)}';
  }

  void _setStatusAbsen() {
    final now = DateTime.now();
    final minutes = now.hour * 60 + now.minute;
    const startOfDay = 8 * 60 + 30;
    const endOfDay = 18 * 60;

    setState(() {
      if (minutes <= startOfDay) {
        _status = 'Attended';
      } else if (minutes <= endOfDay) {
        _status = 'Late';
      } else {
        _status = 'Leave';
      }
    });
  }

  Future<void> _submitAbsen({
    required String alamat,
    required String nama,
    required String status,
  }) async {
    _showLoadingDialog();
    try {
      final now = DateTime.now();
      await FirebaseFirestore.instance.collection('attendance').add({
        'name': nama.trim(),
        'address': alamat.isEmpty ? 'Lokasi tidak terekam' : alamat,
        'description': status,
        'datetime': DateFormat('yyyy-MM-dd HH:mm:ss').format(now),
        'latitude': _latitude,
        'longitude': _longitude,
        'type': 'attendance',
        'created_at': FieldValue.serverTimestamp(),
      });

      if (!mounted) {
        return;
      }

      Navigator.of(context, rootNavigator: true).pop();
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const HomeScreen()),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      Navigator.of(context, rootNavigator: true).pop();
      _showMessage('Gagal mengirim presensi: $error', Colors.redAccent);
    }
  }

  void _showLoadingDialog() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Expanded(child: Text('Menyimpan presensi...')),
            ],
          ),
        );
      },
    );
  }

  void _showMessage(String message, Color backgroundColor) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: backgroundColor),
    );
  }

  Future<void> _processImage(XFile imageFile) async {
    if (_isBusy) {
      return;
    }

    setState(() {
      _isBusy = true;
      _hasFace = false;
    });

    try {
      final inputImage = InputImage.fromFilePath(imageFile.path);
      final faces = await _faceDetector.processImage(inputImage);

      if (!mounted) {
        return;
      }

      setState(() {
        _hasFace = faces.isNotEmpty;
      });

      if (faces.isEmpty) {
        _showMessage(
          'Wajah tidak terdeteksi. Pastikan wajah terlihat jelas di bingkai.',
          Colors.orange,
        );
        return;
      }

      final locationReady = await _getGeoLocation();
      if (!mounted) {
        return;
      }

      if (!locationReady || _locationAddress == null) {
        _showMessage(
          'Wajah terdeteksi, tetapi lokasi belum tersedia.',
          Colors.orange,
        );
        return;
      }

      _setStatusAbsen();
      await _submitAbsen(
        alamat: _locationAddress!,
        nama: 'Siswa XI RPL',
        status: _status,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal memproses wajah: $error'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  Future<void> _captureImage() async {
    final controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        controller.value.isTakingPicture ||
        _isBusy) {
      return;
    }

    try {
      final imageFile = await controller.takePicture();
      await _processImage(imageFile);
    } on CameraException catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Gagal mengambil foto: ${error.description ?? error.code}',
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _faceDetector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Attendance Record')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.camera_alt_outlined,
                size: 56,
                color: Colors.redAccent,
              ),
              const SizedBox(height: 16),
              const Text(
                'Unable to initialize the camera',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black54),
              ),
            ],
          ),
        ),
      );
    }

    if (!_isCameraReady) {
      return const Center(child: CircularProgressIndicator());
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        Center(
          child: AspectRatio(
            aspectRatio: _controller!.value.aspectRatio,
            child: CameraPreview(_controller!),
          ),
        ),
        Center(child: _buildFaceScanner()),
        Positioned(
          left: 24,
          right: 24,
          bottom: 40,
          child: FilledButton.icon(
            onPressed: _isBusy || _isLoadingLocation ? null : _captureImage,
            icon: _isBusy || _isLoadingLocation
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.camera_alt_rounded),
            label: Text(
              _isLoadingLocation
                  ? 'Mengambil lokasi...'
                  : _isBusy
                  ? 'Memproses...'
                  : 'Ambil Foto',
            ),
          ),
        ),
        if (_hasFace)
          const Positioned(
            top: 20,
            left: 20,
            right: 20,
            child: Chip(
              avatar: Icon(Icons.check_circle, color: Colors.white),
              label: Text('Wajah terdeteksi'),
              backgroundColor: Colors.green,
              labelStyle: TextStyle(color: Colors.white),
            ),
          ),
        if (_latitude != null && _longitude != null)
          Positioned(
            left: 20,
            right: 20,
            bottom: 100,
            child: Card(
              color: Colors.black.withValues(alpha: 0.7),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Text(
                  'Lokasi: ${_latitude!.toStringAsFixed(6)}, '
                  '${_longitude!.toStringAsFixed(6)}\n'
                  '${_locationAddress ?? 'Alamat tidak tersedia'}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildFaceScanner() {
    return DottedBorder(
      borderType: BorderType.RRect,
      radius: const Radius.circular(24),
      color: Colors.lightBlueAccent,
      strokeWidth: 2,
      dashPattern: const [8, 4],
      child: SizedBox(
        width: 260,
        height: 340,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Lottie.asset(
              'assets/raw/face_id_ring.json',
              width: 240,
              height: 240,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                return const Icon(
                  Icons.face_retouching_natural,
                  size: 120,
                  color: Colors.lightBlueAccent,
                );
              },
            ),
            const Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: Text(
                  'Posisikan wajah di dalam bingkai',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    shadows: [Shadow(blurRadius: 4, color: Colors.black87)],
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
