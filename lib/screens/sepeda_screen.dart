import 'package:flutter/material.dart';

import '../services/bike_service.dart';

class SepedaScreen extends StatefulWidget {
  const SepedaScreen({super.key, this.bikeService});

  final BikeService? bikeService;

  @override
  State<SepedaScreen> createState() => _SepedaScreenState();
}

class _SepedaScreenState extends State<SepedaScreen> {
  late final BikeService _bikeService = widget.bikeService ?? ApiBikeService();
  List<Bike> _bikes = [];
  bool _isLoading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadBikes();
  }

  Future<void> _loadBikes() async {
    setState(() => _isLoading = true);
    try {
      final bikes = await _bikeService.getBikes();
      if (mounted) {
        setState(() {
          _bikes = bikes;
          _loadError = null;
        });
      }
    } on BikeApiException catch (error) {
      if (mounted) setState(() => _loadError = error.message);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _showAddBikeDialog() async {
    await _showBikeDialog();
  }

  Future<void> _showBikeDialog({Bike? bike}) async {
    final formKey = GlobalKey<FormState>();
    var name = '';
    var number = '';

    final bikeDetails = await showDialog<({String name, String number})>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(bike == null ? 'Tambah Sepeda' : 'Edit Sepeda'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                autofocus: true,
                initialValue: bike?.name,
                decoration: const InputDecoration(labelText: 'Nama sepeda'),
                textCapitalization: TextCapitalization.words,
                maxLength: 120,
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Nama sepeda wajib diisi'
                    : null,
                onSaved: (value) => name = value!.trim(),
              ),
              TextFormField(
                initialValue: bike?.number,
                decoration: const InputDecoration(
                  labelText: 'No. sepeda',
                  hintText: 'Contoh: 0001',
                  counterText: '',
                ),
                keyboardType: TextInputType.number,
                maxLength: 4,
                validator: (value) =>
                    value == null || !RegExp(r'^\d{4}$').hasMatch(value)
                    ? 'Masukkan tepat 4 digit angka'
                    : null,
                onSaved: (value) => number = value!.trim(),
              ),
            ],
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
                Navigator.pop(context, (name: name, number: number));
              }
            },
            child: Text(bike == null ? 'Tambah' : 'Simpan'),
          ),
        ],
      ),
    );

    if (bikeDetails == null || !mounted) return;

    try {
      if (bike == null) {
        await _bikeService.addBike(
          name: bikeDetails.name,
          number: bikeDetails.number,
        );
      } else {
        await _bikeService.updateBike(
          id: bike.id,
          name: bikeDetails.name,
          number: bikeDetails.number,
        );
      }
      await _loadBikes();
    } on BikeApiException catch (error) {
      if (mounted) _showMessage(error.message);
    }
  }

  Future<void> _showGpsDialog(Bike bike) async {
    try {
      final devices = await _bikeService.getGpsDevices();
      if (!mounted) return;
      final availableDevices = devices
          .where(
            (device) =>
                device.isActive &&
                (device.connectedBikeNumber == null ||
                    device.code == bike.gpsCode),
          )
          .toList();
      if (availableDevices.isEmpty) {
        _showMessage('Daftarkan GPS terlebih dahulu di menu Tambah Kode GPS.');
        return;
      }

      var selectedCode =
          bike.gpsCode != null &&
              availableDevices.any((device) => device.code == bike.gpsCode)
          ? bike.gpsCode!
          : availableDevices.first.code;
      final code = await showDialog<String>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text('Hubungkan GPS ke ${bike.number}'),
            content: DropdownButtonFormField<String>(
              initialValue: selectedCode,
              decoration: const InputDecoration(labelText: 'Pilih GPS aktif'),
              items: availableDevices
                  .map(
                    (device) => DropdownMenuItem(
                      value: device.code,
                      child: Text(device.code),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  setDialogState(() => selectedCode = value);
                }
              },
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Batal'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, selectedCode),
                child: const Text('Hubungkan'),
              ),
            ],
          ),
        ),
      );
      if (code == null || !mounted) return;

      await _bikeService.connectGps(bikeId: bike.id, gpsCode: code);
      await _loadBikes();
    } on BikeApiException catch (error) {
      if (mounted) _showMessage(error.message);
    }
  }

  Future<void> _disconnectGps(Bike bike) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Lepaskan GPS?'),
        content: Text('Kode GPS ${bike.gpsCode} akan dilepaskan dari sepeda.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Lepaskan'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await _bikeService.disconnectGps(bike.id);
      await _loadBikes();
    } on BikeApiException catch (error) {
      if (mounted) _showMessage(error.message);
    }
  }

  Future<void> _deleteBike(Bike bike) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus Sepeda?'),
        content: Text(
          '${bike.name} (No. ${bike.number}) akan dihapus permanen'
          '${bike.gpsCode == null ? '.' : ', termasuk koneksi GPS ${bike.gpsCode}.'}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await _bikeService.deleteBike(bike.id);
      await _loadBikes();
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
      appBar: AppBar(
        title: const Text('Daftar Sepeda'),
        actions: [
          IconButton(
            onPressed: _showAddBikeDialog,
            tooltip: 'Tambah sepeda',
            icon: const Icon(Icons.add),
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
                    onPressed: _loadBikes,
                    child: const Text('Coba lagi'),
                  ),
                ],
              ),
            )
          : _bikes.isEmpty
          ? const Center(
              child: Text(
                'Belum ada sepeda.\nTekan + untuk menambahkan.',
                textAlign: TextAlign.center,
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _bikes.length,
              itemBuilder: (context, index) {
                final bike = _bikes[index];
                return Card(
                  child: ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: Color(0xFFE0F2F1),
                      child: Icon(Icons.pedal_bike, color: Color(0xFF2F9C89)),
                    ),
                    title: Text(bike.name),
                    subtitle: Text(
                      'No. Sepeda ${bike.number}\n'
                      'GPS: ${bike.gpsCode ?? 'Belum terhubung'}\n'
                      'Lokasi uji: ${bike.hasLocation ? '${bike.latitude}, ${bike.longitude}' : 'Belum tersedia'}',
                    ),
                    isThreeLine: true,
                    trailing: PopupMenuButton<String>(
                      tooltip: 'Kelola sepeda',
                      onSelected: (action) {
                        switch (action) {
                          case 'edit':
                            _showBikeDialog(bike: bike);
                          case 'connect_gps':
                            _showGpsDialog(bike);
                          case 'disconnect_gps':
                            _disconnectGps(bike);
                          case 'delete':
                            _deleteBike(bike);
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'edit',
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.edit),
                            title: Text('Edit sepeda'),
                          ),
                        ),
                        PopupMenuItem(
                          value: 'connect_gps',
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.gps_fixed),
                            title: Text(
                              bike.gpsCode == null
                                  ? 'Hubungkan GPS'
                                  : 'Ganti GPS',
                            ),
                          ),
                        ),
                        if (bike.gpsCode != null)
                          const PopupMenuItem(
                            value: 'disconnect_gps',
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(Icons.link_off),
                              title: Text('Hapus koneksi GPS'),
                            ),
                          ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              Icons.delete_outline,
                              color: Colors.red,
                            ),
                            title: Text('Hapus sepeda'),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddBikeDialog,
        tooltip: 'Tambah sepeda',
        child: const Icon(Icons.add),
      ),
    );
  }
}
