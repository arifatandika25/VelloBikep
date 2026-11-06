import 'package:flutter/material.dart';

import '../services/bike_service.dart';

class HubungkanGPSScreen extends StatefulWidget {
  const HubungkanGPSScreen({super.key, this.bikeService});

  final BikeService? bikeService;

  @override
  State<HubungkanGPSScreen> createState() => _HubungkanGPSScreenState();
}

class _HubungkanGPSScreenState extends State<HubungkanGPSScreen> {
  late final BikeService _bikeService = widget.bikeService ?? ApiBikeService();
  List<GpsDevice> _devices = [];
  bool _isLoading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  Future<void> _loadDevices() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final devices = await _bikeService.getGpsDevices();
      if (mounted) setState(() => _devices = devices);
    } on BikeApiException catch (error) {
      if (mounted) setState(() => _loadError = error.message);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _registerDevice() async {
    final formKey = GlobalKey<FormState>();
    var code = '';
    final gpsCode = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Tambah Kode GPS'),
        content: Form(
          key: formKey,
          child: TextFormField(
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Kode/serial GPS',
              hintText: 'Contoh: GPS-001',
            ),
            textCapitalization: TextCapitalization.characters,
            maxLength: 120,
            validator: (value) => value == null || value.trim().isEmpty
                ? 'Kode GPS wajib diisi'
                : null,
            onSaved: (value) => code = value!.trim().toUpperCase(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                formKey.currentState!.save();
                Navigator.pop(context, code);
              }
            },
            child: const Text('Aktifkan'),
          ),
        ],
      ),
    );
    if (gpsCode == null || !mounted) return;

    try {
      await _bikeService.registerGpsDevice(gpsCode);
      await _loadDevices();
      if (mounted) {
        _showMessage(
          'GPS dummy diaktifkan. Koordinat uji Yogyakarta sudah disiapkan.',
        );
      }
    } on BikeApiException catch (error) {
      if (mounted) _showMessage(error.message);
    }
  }

  Future<void> _deleteDevice(GpsDevice device) async {
    if (device.connectedBikeNumber != null) {
      _showMessage(
        'Lepaskan GPS dari sepeda ${device.connectedBikeNumber} terlebih dahulu.',
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus Kode GPS?'),
        content: Text('Kode ${device.code} akan dihapus dari daftar GPS.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _bikeService.deleteGpsDevice(device.id);
      await _loadDevices();
    } on BikeApiException catch (error) {
      if (mounted) _showMessage(error.message);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Kode GPS', style: TextStyle(color: Colors.black)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        actions: [
          IconButton(
            onPressed: _loadDevices,
            tooltip: 'Muat ulang',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_loadError!, textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: _loadDevices,
                    child: const Text('Coba lagi'),
                  ),
                ],
              ),
            )
          : _devices.isEmpty
          ? const Center(
              child: Text(
                'Belum ada kode GPS.\nTekan + untuk menambahkan.',
                textAlign: TextAlign.center,
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _devices.length,
              itemBuilder: (context, index) {
                final device = _devices[index];
                final connectedTo = device.connectedBikeNumber;
                return Card(
                  child: ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: Color(0xFFE0F2F1),
                      child: Icon(Icons.gps_fixed, color: Color(0xFF2F9C89)),
                    ),
                    title: Text(device.code),
                    subtitle: Text(
                      'Aktif · Lokasi uji: '
                      '${device.latitude}, ${device.longitude}\n'
                      '${connectedTo == null ? 'Belum terhubung ke sepeda' : 'Terhubung ke sepeda $connectedTo'}',
                    ),
                    isThreeLine: true,
                    trailing: IconButton(
                      tooltip: 'Hapus kode GPS',
                      onPressed: () => _deleteDevice(device),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _registerDevice,
        tooltip: 'Tambah kode GPS',
        child: const Icon(Icons.add),
      ),
    );
  }
}
