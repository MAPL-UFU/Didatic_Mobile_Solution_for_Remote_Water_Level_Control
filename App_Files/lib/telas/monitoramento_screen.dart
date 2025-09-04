import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import '../globals.dart';

class MonitoramentoScreen extends StatefulWidget {
  const MonitoramentoScreen({super.key});

  @override
  State<MonitoramentoScreen> createState() => _MonitoramentoScreenState();
}

class _MonitoramentoScreenState extends State<MonitoramentoScreen> {
  MqttServerClient? client;
  String _connectionStatus = "Iniciando...";

  String _alunoIdAtivo = "Nenhum aluno conectado";
  String _statusBancada = "--";
  String _nivelAgua = "--";
  String _tensao = "--";
  String _tempo = "--";
  String _paramRef = "--";
  String _paramK = "--";
  String _paramKe = "--";
  String _paramNx = "--";
  String _paramNu = "--";

  @override
  void initState() {
    super.initState();
    if (AppGlobals.tipoUsuario == 'Professor') {
      _connectToBroker();
    }
  }

  @override
  void dispose() {
    client?.disconnect();
    super.dispose();
  }

  Future<void> _connectToBroker() async {
    final String? brokerIp = AppGlobals.ipBrokerMQTT;

    if (brokerIp == null || brokerIp.isEmpty) {
      if (mounted)
        setState(
          () => _connectionStatus =
              "IP do Broker não configurado na tela de 'Configuração'.",
        );
      return;
    }

    final clientId =
        'professor_monitor_${DateTime.now().millisecondsSinceEpoch}';
    client = MqttServerClient(brokerIp, clientId);
    client!.port = 1883;
    client!.logging(on: false);
    client!.keepAlivePeriod = 30;

    client!.onDisconnected = _onDisconnected;
    client!.onConnected = _onConnected;

    final connMessage = MqttConnectMessage()
        .withClientIdentifier(clientId)
        .startClean();
    client!.connectionMessage = connMessage;

    try {
      if (mounted)
        setState(
          () => _connectionStatus = "Conectando ao Broker em $brokerIp...",
        );
      await client!.connect();
    } on Exception {
      client!.disconnect();
    }

    if (client!.connectionStatus!.state != MqttConnectionState.connected) {
      _onDisconnected();
    }
  }

  void _onConnected() {
    if (mounted)
      setState(() => _connectionStatus = "Conectado. Aguardando aluno...");

    client!.updates!.listen((List<MqttReceivedMessage<MqttMessage?>>? c) {
      if (c == null || c.isEmpty) return;
      final MqttPublishMessage recMess = c[0].payload as MqttPublishMessage;
      final String message = MqttPublishPayload.bytesToStringAsString(
        recMess.payload.message,
      );
      final String topic = c[0].topic;

      if (topic == 'entradaid' && _alunoIdAtivo != message) {
        if (_alunoIdAtivo != "Nenhum aluno conectado") {
          client!.unsubscribe('bancada/$_alunoIdAtivo/#');
          client!.unsubscribe('$_alunoIdAtivo/#');
        }

        if (mounted) {
          setState(() {
            _alunoIdAtivo = message;
            _connectionStatus = "Monitorando Aluno: $_alunoIdAtivo";

            _statusBancada = _nivelAgua = _tensao = _tempo = _paramRef =
                _paramK = _paramKe = _paramNx = _paramNu = "--";
          });
        }
        client!.subscribe('bancada/$_alunoIdAtivo/#', MqttQos.atLeastOnce);
        client!.subscribe('$_alunoIdAtivo/#', MqttQos.atLeastOnce);
      }

      if (mounted) {
        setState(() {
          if (topic.endsWith('/status'))
            _statusBancada = message;
          else if (topic.endsWith('/nivelagua'))
            _nivelAgua = '$message cm';
          else if (topic.endsWith('/tensao'))
            _tensao = '$message %';
          else if (topic.endsWith('/tempo'))
            _tempo = '$message s';
          else if (topic.endsWith('/ref'))
            _paramRef = message;
          else if (topic.endsWith('/k'))
            _paramK = message;
          else if (topic.endsWith('/ke'))
            _paramKe = message;
          else if (topic.endsWith('/nx'))
            _paramNx = message;
          else if (topic.endsWith('/nu'))
            _paramNu = message;
        });
      }
    });

    client!.subscribe('entradaid', MqttQos.atLeastOnce);
  }

  void _onDisconnected() {
    if (mounted)
      setState(
        () => _connectionStatus =
            "Desconectado. Verifique o IP do Broker e a rede.",
      );
  }

  Widget _buildInfoCard(
    String title,
    String value,
    IconData icon,
    Color iconColor,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 2.0,
      margin: const EdgeInsets.symmetric(vertical: 6.0),
      child: ListTile(
        leading: Icon(icon, color: iconColor, size: 36),
        title: Text(
          title,
          style: TextStyle(color: colorScheme.onSurfaceVariant),
        ),
        trailing: Text(
          value,
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (AppGlobals.tipoUsuario != 'Professor') {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Text(
            "Esta tela está disponível apenas para o perfil de Professor.",
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: ListView(
        children: [
          Text(
            _connectionStatus,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          Text("Aluno Ativo", style: theme.textTheme.titleLarge),
          _buildInfoCard(
            "Matrícula",
            _alunoIdAtivo,
            Icons.person,
            Colors.blueGrey,
          ),
          const Divider(height: 32),
          Text(
            "Dados da Bancada (Em Tempo Real)",
            style: theme.textTheme.titleLarge,
          ),
          _buildInfoCard(
            "Status",
            _statusBancada,
            Icons.monitor_heart_outlined,
            Colors.deepPurple,
          ),
          _buildInfoCard("Nível da Água", _nivelAgua, Icons.waves, Colors.blue),
          _buildInfoCard(
            "Tensão na Bomba",
            _tensao,
            Icons.flash_on,
            Colors.orange,
          ),
          _buildInfoCard(
            "Tempo de Experimento",
            _tempo,
            Icons.timer_outlined,
            Colors.grey,
          ),
          const Divider(height: 32),
          Text(
            "Parâmetros Enviados pelo Aluno",
            style: theme.textTheme.titleLarge,
          ),
          _buildInfoCard(
            "Referência (ref)",
            _paramRef,
            Icons.track_changes,
            Colors.red,
          ),
          _buildInfoCard("Ganho (k)", _paramK, Icons.tune, Colors.green),
          _buildInfoCard(
            "Ganho do Observador (ke)",
            _paramKe,
            Icons.visibility,
            Colors.green,
          ),
          _buildInfoCard(
            "Ganho de Pré-Compensação (Nx)",
            _paramNx,
            Icons.functions,
            Colors.green,
          ),
          _buildInfoCard(
            "Ganho de Regime (Nu)",
            _paramNu,
            Icons.settings_ethernet,
            Colors.green,
          ),
        ],
      ),
    );
  }
}
