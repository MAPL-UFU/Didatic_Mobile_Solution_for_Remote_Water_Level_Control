import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'broker.dart';
import 'dadosexperimento.dart';

class Experimento extends StatefulWidget {
  const Experimento({super.key});
  @override
  State<Experimento> createState() => _ExperimentoState();
}

class _ExperimentoState extends State<Experimento> {
  final TextEditingController referenciaController = TextEditingController();
  String wifiStatus = "";
  String brokerStatus = "";
  String experimentoStatus = "";
  late MqttClient client;
  final BrokerInfo brokerInfo = BrokerInfo();
  List<Map<String, String>> tableData = [];
  late Timer _reconnectTimer;

  @override
  void initState() {
    super.initState();
    _connectToMqtt();
    final dados = ExperimentoData();
    referenciaController.text = dados.valores['referencia']!;
    referenciaController.addListener(
        () => dados.valores['referencia'] = referenciaController.text);
    _reconnectTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (client.connectionStatus?.state != MqttConnectionState.connected) {
        _connectToMqtt();
      }
    });
  }

  @override
  void dispose() {
    _reconnectTimer.cancel();
    super.dispose();
  }

  void _connectToMqtt() async {
    client = MqttServerClient(brokerInfo.ip, 'flutter_experimento');
    client.port = brokerInfo.porta;
    client.keepAlivePeriod = 20;
    if (brokerInfo.credenciais) {
      client.setProtocolV311();
      client.connectionMessage = MqttConnectMessage()
          .withClientIdentifier('flutter_experimento')
          .authenticateAs(brokerInfo.usuario, brokerInfo.senha)
          .startClean();
    }
    try {
      await client.connect();
      if (client.connectionStatus?.state == MqttConnectionState.connected) {
        _subscribeToTopics();
        _setupMessageListener();
        mostrarNotificacao(context, 'Conectado ao Broker!');
      }
    } catch (e) {
      if (mounted) {
        mostrarNotificacao(context, 'Desconectado do Broker!');
      }
    }
  }

  void _subscribeToTopics() {
    client.subscribe('estadoESPWifi', MqttQos.atMostOnce);
    client.subscribe('estadoESPBroker', MqttQos.atMostOnce);
    client.subscribe('estadoExperimento', MqttQos.atMostOnce);
    client.subscribe('tempo', MqttQos.atMostOnce);
    client.subscribe('nivel', MqttQos.atMostOnce);
    client.subscribe('tensao', MqttQos.atMostOnce);
    client.subscribe('estimado', MqttQos.atMostOnce);
  }

  void _setupMessageListener() {
    client.updates!.listen((List<MqttReceivedMessage<MqttMessage>> c) {
      for (final msg in c) {
        final payload = msg.payload as MqttPublishMessage;
        final topic = msg.topic;
        final message =
            MqttPublishPayload.bytesToStringAsString(payload.payload.message);
        if (topic == 'estadoESPWifi') {
          setState(() => wifiStatus = message);
        } else if (topic == 'estadoESPBroker') {
          setState(() => brokerStatus = message);
        } else if (topic == 'estadoExperimento') {
          setState(() => experimentoStatus = message);
        } else if (topic == 'tempo') {
          _handleDataUpdate('tempo', message);
        } else if (topic == 'nivel') {
          _handleDataUpdate('nivel', message);
        } else if (topic == 'tensao') {
          _handleDataUpdate('tensao', message);
        }
      }
    });
  }

  void mostrarNotificacao(BuildContext context, String mensagem) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Erro', style: TextStyle(color: Colors.red)),
        content: Text(mensagem),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _handleDataUpdate(String type, String message) {
    try {
      final double value = double.parse(message);
      final int timestamp = DateTime.now().millisecondsSinceEpoch;
      
      final entryIndex =
          tableData.indexWhere((e) => e['timestamp'] == timestamp.toString());
      if (entryIndex == -1) {
        tableData.add({
          'timestamp': timestamp.toString(),
          'tempo': type == 'tempo' ? value.toStringAsFixed(1) : "",
          'nivel': type == 'nivel' ? value.toStringAsFixed(1) : "",
          'tensao': type == 'tensao' ? value.toStringAsFixed(1) : "",
          'estimado': type == 'estimado' ? value.toStringAsFixed(1) : "",
        });
      } else {
        tableData[entryIndex][type] = value.toStringAsFixed(1);
      }
      setState(() {});
    } catch (e) {
      mostrarNotificacao(context, 'Formato inválido: $message');
    }
  }

  void _publicarReferencia() {
    if (referenciaController.text.isEmpty) return;
    final builder = MqttClientPayloadBuilder();
    builder.addDouble(double.parse(referenciaController.text));
    
    client.publishMessage('referencia_app', MqttQos.atLeastOnce, builder.payload!);
  }

  void _encerrarExperimento() {
    final builder = MqttClientPayloadBuilder();
    builder.addString('ENCERRAR');
    client.publishMessage(
        'encerraExperimento', MqttQos.exactlyOnce, builder.payload!);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: Builder(builder: (context) {
          return IconButton(
            onPressed: () => Scaffold.of(context).openDrawer(),
            icon: const Icon(Icons.menu, color: Colors.white),
          );
        }),
        title: const Text('Controle do Experimento',
            style:
                TextStyle(fontSize: 25, fontWeight: FontWeight.bold, color: Colors.white)),
        centerTitle: true,
        backgroundColor: const Color.fromRGBO(19, 85, 156, 1),
        drawer: _buildDrawer(),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(25.0),
              child: Column(
                children: [
                  _buildStatusContainer(),
                  const SizedBox(height: 20),
                  _buildReferenceInput(),
                  const SizedBox(height: 20),
                  _buildControlButtons(),
                  const SizedBox(height: 20),
                  _buildDataTable(),
                ],
              ),
            ),
          ),
          _buildBottomNavBar(),
        ],
      ),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      backgroundColor: const Color.fromRGBO(19, 85, 156, 1),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 80),
                Row(
                  children: [
                    Icon(
                      brokerInfo.status == 'Conectado'
                          ? Icons.cloud_done
                          : Icons.cloud_off,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Status Broker: ${brokerInfo.status}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    const Icon(Icons.router, color: Colors.white),
                    const SizedBox(width: 8),
                    Text(
                      'Ip: ${brokerInfo.ip}',
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    const Icon(Icons.door_front_door, color: Colors.white),
                    const SizedBox(width: 8),
                    Text(
                      'Porta: ${brokerInfo.porta}',
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                if (brokerInfo.credenciais) ...[
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      const Icon(Icons.person, color: Colors.white),
                      const SizedBox(width: 8),
                      Text(
                        'Usuario: ${brokerInfo.usuario}',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      const Icon(Icons.lock, color: Colors.white),
                      const SizedBox(width: 8),
                      Text(
                        'Senha: ${brokerInfo.senha}',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusContainer() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.blueGrey),
      ),
      child: Column(
        children: [
          _buildStatusRow('WiFi ESP:', wifiStatus),
          const SizedBox(height: 10),
          _buildStatusRow('Broker ESP:', brokerStatus),
          const SizedBox(height: 10),
          _buildStatusRow('Experimento:', experimentoStatus),
        ],
      ),
    );
  }

  Widget _buildStatusRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        Text(value, style: const TextStyle(color: Colors.blueGrey)),
      ],
    );
  }

  Widget _buildReferenceInput() {
    return TextFormField(
      controller: referenciaController,
      decoration: InputDecoration(
        icon: const Icon(Icons.settings_input_component,
            color: Color.fromRGBO(19, 85, 156, 1)),
        labelText: 'Referência de Nível (cm)',
        labelStyle: const TextStyle(color: Color.fromRGBO(19, 85, 156, 1)),
        suffixIcon: IconButton(
          icon: const Icon(Icons.info, color: Color.fromRGBO(19, 85, 156, 1)),
          onPressed: () => _showInfoDialog(context),
        ),
      ),
      keyboardType: TextInputType.number,
    );
  }

  Widget _buildControlButtons() {
    return Column(
      children: [
        ElevatedButton(
          onPressed: _publicarReferencia,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color.fromRGBO(19, 85, 156, 1),
            padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          ),
          child: const Text('Publicar Referência',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white)),
        ),
        const SizedBox(height: 10),
        ElevatedButton(
          onPressed: _encerrarExperimento,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red[700],
            padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          ),
          child: const Text('Encerrar Experimento',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white)),
        ),
      ],
    );
  }

  Widget _buildDataTable() {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          const Text('Dados em Tempo Real',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 15),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columnSpacing: 30,
              columns: const [
                DataColumn(label: Text('Tempo (s)')),
                DataColumn(label: Text('Nível (cm)')),
                DataColumn(label: Text('Tensão (V)')),
                DataColumn(label: Text('Estimado)')), 
              ],
              rows: tableData
                  .map((data) => DataRow(
                        cells: [
                          DataCell(Text(data['tempo'] ?? '0.0')),
                          DataCell(Text(data['nivel'] ?? '0.0')),
                          DataCell(Text(data['tensao'] ?? '0.0')),
                          DataCell(Text(data['estimado'] ?? '0.0')), 
                        ],
                      ))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNavBar() {
    return Container(
      height: 60,
      decoration: const BoxDecoration(
        color: Color.fromRGBO(19, 85, 156, 1),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          IconButton(
            icon: const Icon(Icons.cloud, color: Colors.white),
            onPressed: () => Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const ConectaBroker()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.assignment, color: Colors.white),
            onPressed: () => Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                  builder: (context) => const DadosExperimentos()),
            ),
          ),
          const IconButton(
            icon: Icon(Icons.science, color: Colors.white),
            onPressed: null,
          ),
        ],
      ),
    );
  }

  void _showInfoDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Informação da Referência'),
        content:
            const Text('Digite o valor desejado para o nível de água entre 3 e 15 cm'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}
