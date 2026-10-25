import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:sms_app/app/initialize/color_constants.dart';
import 'package:sms_app/app/initialize/custom_app_bar.dart';
import 'package:sms_app/app/services/payment_api_service.dart';
import 'package:sms_app/app/services/payment_token_store.dart';

/// Payment gateway settings. The receiver is read from /api/phone and the
/// gateway token can be updated without rebuilding the application.
class SimSettingsView extends StatefulWidget {
  const SimSettingsView({super.key});

  @override
  State<SimSettingsView> createState() => _SimSettingsViewState();
}

class _SimSettingsViewState extends State<SimSettingsView> {
  final PaymentApiService _api = PaymentApiService();
  final PaymentTokenStore _tokenStore = PaymentTokenStore();
  late final TextEditingController _tokenController;
  String? _receiver;
  String? _receiverError;
  bool _loadingReceiver = true;
  bool _showToken = false;

  @override
  void initState() {
    super.initState();
    _tokenController = TextEditingController(text: _tokenStore.token);
    _loadReceiver();
  }

  Future<void> _loadReceiver() async {
    setState(() {
      _loadingReceiver = true;
      _receiverError = null;
    });
    try {
      final receiver = await _api.fetchReceiver();
      if (mounted) setState(() => _receiver = receiver);
    } catch (e) {
      if (mounted) {
        setState(() => _receiverError = e is FormatException
            ? e.message
            : e.toString());
      }
    } finally {
      if (mounted) setState(() => _loadingReceiver = false);
    }
  }

  Future<void> _saveToken() async {
    try {
      await _tokenStore.save(_tokenController.text);
      Get.snackbar('Сохранено', 'Токен обновлён',
          snackPosition: SnackPosition.BOTTOM);
    } on ArgumentError {
      Get.snackbar('Ошибка', 'Токен не может быть пустым',
          snackPosition: SnackPosition.BOTTOM);
    }
  }

  @override
  void dispose() {
    _tokenController.dispose();
    _api.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar:
          const CustomAppBar(title: 'Настройки оплаты', showBackButton: true),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              title: const Text('Номер получателя'),
              subtitle: Text(_loadingReceiver
                  ? 'Загрузка…'
                  : _receiverError ?? _receiver ?? 'Номер не найден'),
              trailing: IconButton(
                tooltip: 'Обновить',
                onPressed: _loadingReceiver ? null : _loadReceiver,
                icon: const Icon(Icons.refresh),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('PHONE_PAYMENT_TOKEN',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _tokenController,
                    obscureText: !_showToken,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      labelText: 'Токен',
                      suffixIcon: IconButton(
                        tooltip: _showToken ? 'Скрыть' : 'Показать',
                        onPressed: () =>
                            setState(() => _showToken = !_showToken),
                        icon: Icon(_showToken
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: ColorConstants.primaryColor,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: _saveToken,
                      child: const Text('Сохранить токен',
                          style: TextStyle(color: Colors.white)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
