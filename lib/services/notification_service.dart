import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'native_bridge.dart';

class AppNotification {
  AppNotification(this.title, this.body, {this.icon = Icons.notifications_rounded, this.gameId, this.imageUrl})
      : time = DateTime.now();
  final String title;
  final String body;
  final IconData icon;

  /// Imagem no lugar do ícone (ex.: badge da conquista desbloqueada).
  final String? imageUrl;
  final String? gameId;
  final DateTime time;
  bool read = false;
}

/// Central de notificações: toasts dentro do app + notificação do sistema
/// (Android) para eventos importantes como atualizações disponíveis.
class NotificationService extends ChangeNotifier {
  final List<AppNotification> items = [];
  final _toasts = StreamController<AppNotification>.broadcast();

  Stream<AppNotification> get toasts => _toasts.stream;
  int get unread => items.where((n) => !n.read).length;

  void push(String title, String body,
      {IconData icon = Icons.notifications_rounded, String? gameId, bool system = false, String? imageUrl}) {
    final n = AppNotification(title, body, icon: icon, gameId: gameId, imageUrl: imageUrl);
    items.insert(0, n);
    if (items.length > 100) items.removeLast();
    _toasts.add(n);
    if (system && Platform.isAndroid) NativeBridge.notify(title, body, id: (gameId ?? title).hashCode & 0x7fffffff);
    notifyListeners();
  }

  void markAllRead() {
    for (final n in items) {
      n.read = true;
    }
    notifyListeners();
  }
}
