import 'package:flutter/material.dart';

import 'lab/connection_lab_page.dart';

void main() {
  runApp(const AppMusica());
}

class AppMusica extends StatelessWidget {
  const AppMusica({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AppMusica',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
      ),
      home: const TelaInicial(),
    );
  }
}

/// Tela provisória da Fase 0. Ainda não há player nem Jam.
class TelaInicial extends StatelessWidget {
  const TelaInicial({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('AppMusica')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Fase 0: validação técnica', style: textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                'Protótipo experimental. Nenhuma função de música disponível ainda.',
                style: textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ConnectionLabPage(),
                  ),
                ),
                child: const Text('Laboratório: conexão'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
