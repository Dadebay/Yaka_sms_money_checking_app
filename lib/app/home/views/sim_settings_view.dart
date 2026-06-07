import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:kartal/kartal.dart';
import 'package:sms_app/app/initialize/color_constants.dart';
import 'package:sms_app/app/initialize/custom_app_bar.dart';
import 'package:sms_app/app/services/sim_number_store.dart';
import 'package:sms_app/app/services/sim_service.dart';

import '../controllers/home_controller.dart';

/// Lets the user view detected SIMs and set the phone number for each SIM,
/// used as the transaction `receiver`. Carrier numbers are auto-filled when
/// available; otherwise the user enters them here.
class SimSettingsView extends StatefulWidget {
  const SimSettingsView({super.key});

  @override
  State<SimSettingsView> createState() => _SimSettingsViewState();
}

class _SimSettingsViewState extends State<SimSettingsView> {
  final HomeController _controller = Get.find();
  final SimNumberStore _store = SimNumberStore();

  bool _loading = true;
  List<SimInfo> _sims = [];
  final Map<int, TextEditingController> _fields = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final sims = await _controller.simService.getActiveSims();
    final manual = _store.read();
    for (final sim in sims) {
      final existing = manual[sim.subId.toString()];
      final initial = (existing != null && existing.isNotEmpty)
          ? existing
          : sim.number;
      _fields[sim.subId] = TextEditingController(text: initial);
    }
    setState(() {
      _sims = sims;
      _loading = false;
    });
  }

  void _save() {
    for (final sim in _sims) {
      final text = _fields[sim.subId]?.text ?? '';
      _store.setNumber(sim.subId, text);
    }
    _controller.refreshSimNumbers();
    Get.snackbar(
      'Сохранено',
      'Номера SIM обновлены',
      snackPosition: SnackPosition.BOTTOM,
    );
  }

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppBar(title: "SIM-карты", showBackButton: true),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _sims.isEmpty
              ? Center(
                  child: Padding(
                    padding: context.padding.normal,
                    child: Text(
                      "SIM-карты не найдены. Проверьте разрешение на телефон.",
                      textAlign: TextAlign.center,
                      style: context.general.textTheme.titleMedium,
                    ),
                  ),
                )
              : ListView(
                  padding: context.padding.normal,
                  children: [
                    ..._sims.map(_buildSimCard),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: ColorConstants.primaryColor,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: _save,
                        child: const Text(
                          "Сохранить",
                          style: TextStyle(
                              color: ColorConstants.whiteColor,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildSimCard(SimInfo sim) {
    final subtitle = [
      "Слот ${sim.slotIndex + 1}",
      if (sim.carrierName.isNotEmpty) sim.carrierName,
      if (sim.displayName.isNotEmpty) sim.displayName,
    ].join(" · ");

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(subtitle,
                style: context.general.textTheme.titleMedium!
                    .copyWith(fontWeight: FontWeight.bold)),
            if (sim.number.isNotEmpty)
              Text("С SIM: ${sim.number}",
                  style: context.general.textTheme.bodySmall!
                      .copyWith(color: ColorConstants.greyColor)),
            const SizedBox(height: 8),
            TextField(
              controller: _fields[sim.subId],
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: "Номер телефона (получатель)",
                hintText: "+993...",
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
