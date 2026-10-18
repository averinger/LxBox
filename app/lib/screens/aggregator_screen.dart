import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AggregatorScreen extends StatefulWidget {
  const AggregatorScreen({super.key});

  @override
  State<AggregatorScreen> createState() => _AggregatorScreenState();
}

class _AggregatorScreenState extends State<AggregatorScreen> {
  bool _isLoading = false;
  String _status = 'Готов к работе';
  List<String> _results = [];
  double _progress = 0.0;

  // Ссылки на источники (можно добавить свои)
  final List<String> _sources = [
    'https://raw.githubusercontent.com/MatinGhanbari/v2ray-configs/main/subscriptions/filtered/subs/vless.txt',
    'https://raw.githubusercontent.com/MatinGhanbari/v2ray-configs/main/subscriptions/filtered/subs/vmess.txt',
    'https://raw.githubusercontent.com/sevcator/5ubscrpt10n/main/protocols/vl.txt',
  ];

  Future<void> _startAggregation() async {
    setState(() {
      _isLoading = true;
      _results.clear();
      _progress = 0.0;
      _status = 'Скачивание списков...';
    });

    List<String> allLines = [];

    // 1. Скачивание
    for (int i = 0; i < _sources.length; i++) {
      try {
        final client = HttpClient();
        final request = await client.getUrl(Uri.parse(_sources[i]));
        final response = await request.close();
        final content = await response.transform(utf8.decoder).join();
        
        // Декодируем Base64, если нужно
        String decoded = content;
        if (!content.contains('://')) {
          try {
            decoded = utf8.decode(base64.decode(content.replaceAll(RegExp(r'\s+'), '')));
          } catch (_) {}
        }
        
        final lines = decoded.split('\n').where((l) => l.contains('://')).toList();
        allLines.addAll(lines);
      } catch (e) {
        // Игнорируем ошибки скачивания конкретного источника
      }
      setState(() {
        _progress = (i + 1) / _sources.length * 0.5; // 50% на скачивание
      });
    }

    // Удаляем дубликаты
    allLines = allLines.toSet().toList();
    setState(() => _status = 'Скачано ${allLines.length} конфигов. Проверка пинга...');

    // 2. Проверка пинга (TCP)
    List<String> working = [];
    for (int i = 0; i < allLines.length; i++) {
      String line = allLines[i];
      try {
        // Извлекаем host и port из URI (упрощенно для vless/vmess)
        Uri? uri;
        if (line.startsWith('vless://') || line.startsWith('trojan://')) {
          uri = Uri.parse(line);
        } else if (line.startsWith('vmess://')) {
          // Парсинг vmess (Base64 JSON) опустим для простоты, чтобы не усложнять код
          continue; 
        }

        if (uri != null && uri.host.isNotEmpty && uri.port != 0) {
          final stopwatch = Stopwatch()..start();
          final socket = await Socket.connect(uri.host, uri.port, timeout: const Duration(seconds: 2));
          stopwatch.stop();
          socket.destroy();

          if (stopwatch.elapsedMilliseconds <= 120) {
            working.add(line);
          }
        }
      } catch (_) {
        // Таймаут или отказ в соединении — пропускаем
      }

      if (i % 10 == 0) {
        setState(() {
          _progress = 0.5 + (i / allLines.length * 0.5);
          _status = 'Проверено $i из ${allLines.length}. Найдено: ${working.length}';
        });
      }
    }

    setState(() {
      _isLoading = false;
      _progress = 1.0;
      _results = working;
      _status = 'Готово! Найдено ${working.length} серверов (≤120ms)';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Агрегатор VPN')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _startAggregation,
              icon: const Icon(Icons.refresh),
              label: const Text('Собрать и проверить серверы'),
            ),
            const SizedBox(height: 16),
            LinearProgressIndicator(value: _progress),
            const SizedBox(height: 8),
            Text(_status, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            Expanded(
              child: _results.isEmpty
                  ? const Center(child: Text('Список пуст'))
                  : ListView.builder(
                      itemCount: _results.length,
                      itemBuilder: (context, index) {
                        final line = _results[index];
                        return Card(
                          child: ListTile(
                            title: Text(
                              line,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12),
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.copy),
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: line));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Скопировано')),
                                );
                              },
                            ),
                          ),
                        );
                      },
                    ),
            ),
            if (_results.isNotEmpty)
              ElevatedButton.icon(
                onPressed: () {
                  final text = _results.join('\n');
                  Clipboard.setData(ClipboardData(text: text));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Все серверы скопированы в буфер!')),
                  );
                },
                icon: const Icon(Icons.copy_all),
                label: const Text('Скопировать всё'),
              ),
          ],
        ),
      ),
    );
  }
}
