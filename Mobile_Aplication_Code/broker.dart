import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'main.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:lottie/lottie.dart';
import 'dadosexperimento.dart';
import 'experimento.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: const ConectaBroker(),
      navigatorKey: BrokerInfo.instance.navigatorKey,
    );
  }
}

class BrokerInfo {
  static final BrokerInfo instance = BrokerInfo._internal();
  factory BrokerInfo() => instance;
  BrokerInfo._internal();
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  MqttServerClient? client;
  String ip = "";
  int porta = 1883;
  String usuario = "";
  String senha = "";
  bool credenciais = true;
  String status = 'Desconectado';
  ValueNotifier<String?> streamUrl = ValueNotifier<String?>(null);

  Future<void> connect({
    required String ip,
    required int porta,
    required String usuario,
    required String senha,
    required bool credenciais,
  }) async {
    try {
      this.ip = ip;
      this.porta = porta;
      this.usuario = usuario;
      this.senha = senha;
      this.credenciais = credenciais;
      client = MqttServerClient(ip, 'flutter_client');
      client!
        ..port = porta
        ..logging(on: false)
        ..keepAlivePeriod = 30
        ..autoReconnect = true
        ..resubscribeOnAutoReconnect = true
        ..onConnected = _onConnected
        ..onDisconnected = _onDisconnected;
      if (credenciais) {
        await client!.connect(usuario, senha);
      } else {
        await client!.connect(null, null);
      }
      if (client!.connectionStatus!.state == MqttConnectionState.connected) {
        status = 'Conectado';
        _subscribeToTopics();
      }
    } catch (e) {
      status = 'Erro de conexão';
      _showErrorDialog('Erro: ${e.toString()}');
    }
  }

  Future<void> disconnect() async {
    client?.disconnect();
    status = 'Desconectado';
    streamUrl.value = null;
    navigatorKey.currentState?.popUntil((route) => route.isFirst);
  }

  void _onConnected() {
    status = 'Conectado';
  }

  void _onDisconnected() {
    status = 'Desconectado';
  }

  void _subscribeToTopics() {
    client?.subscribe('observadorKe', MqttQos.atLeastOnce);
    client?.subscribe('reguladorK', MqttQos.atLeastOnce);
    client?.subscribe('nx', MqttQos.atLeastOnce);
    client?.subscribe('nu', MqttQos.atLeastOnce);
    client?.subscribe('streamExperimento', MqttQos.atLeastOnce);
    client?.updates?.listen((List<MqttReceivedMessage<MqttMessage>> messages) {
      for (var msg in messages) {
        final topic = msg.topic;
        final payload = msg.payload as MqttPublishMessage;
        final message = MqttPublishPayload.bytesToStringAsString(
          payload.payload.message,
        );
        if (topic == 'streamExperimento') {
          streamUrl.value = message;
        }
      }
    });
  }

  void publish(String topic, String message) {
    if (client?.connectionStatus?.state == MqttConnectionState.connected) {
      _publishMessage(topic, message);
    }
  }

  void _publishMessage(String topic, String message) {
    final builder = MqttClientPayloadBuilder();
    builder.addString(message);
    client?.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
  }

  void _showErrorDialog(String message) {
    navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (context) => AlertDialog(
          title: const Text('Erro'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      ),
    );
  }
}

class ConectaBroker extends StatefulWidget {
  const ConectaBroker({super.key});
  @override
  State<ConectaBroker> createState() => _ConectaBrokerState();
}

class _ConectaBrokerState extends State<ConectaBroker> {
  final TextEditingController ipControler = TextEditingController();
  final TextEditingController portaControler = TextEditingController(
    text: '1883',
  );
  final TextEditingController usuarioControler = TextEditingController();
  final TextEditingController senhaControler = TextEditingController();
  final BrokerInfo brokerInfo = BrokerInfo.instance;
  Future<void> _connect() async {
    final connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult == ConnectivityResult.none) {
      _showDialog('Erro!', 'Sem conexão com a internet');
      return;
    }
    try {
      await brokerInfo.connect(
        ip: ipControler.text.trim(),
        porta: int.tryParse(portaControler.text.trim()) ?? 1883,
        usuario: usuarioControler.text.trim(),
        senha: senhaControler.text.trim(),
        credenciais: brokerInfo.credenciais,
      );
      if (brokerInfo.status == 'Conectado') {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Sucesso!'),
            content: const Text('Conectado ao broker com sucesso'),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const DadosExperimentos(),
                    ),
                  );
                },
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      _showDialog('Erro', 'Falha na conexão com o broker: ${e.toString()}');
    }
    setState(() {});
  }

  Future<void> _disconnect() async {
    await brokerInfo.disconnect();
    _showDialog('Desconectado', 'Você foi desconectado do broker.');
    setState(() {});
  }

  void _showDialog(String titulo, String mensagem) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(titulo),
        content: Text(mensagem),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: Builder(
          builder: (context) => IconButton(
            onPressed: () => Scaffold.of(context).openDrawer(),
            icon: const Icon(Icons.menu, color: Colors.white),
          ),
        ),
        title: const Text(
          'Informações do Broker',
          style: TextStyle(
            fontSize: 25,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        centerTitle: true,
        backgroundColor: const Color.fromRGBO(19, 85, 156, 1),
        actions: [
          IconButton(
            onPressed: _confimacaoLimparDados,
            icon: const Icon(Icons.close, color: Colors.white),
          ),
        ],
      ),
      drawer: Drawer(
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
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(25.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (brokerInfo.status == 'Conectado')
                    Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: MediaQuery.of(context).size.width * 0.7,
                            height: 140,
                            child: Lottie.asset('assets/TudoCerto.json'),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 20),
                            child: Text(
                              'Você está conectado ao broker!',
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.green,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          const SizedBox(height: 30),
                        ],
                      ),
                    ),
                  TextFormField(
                    controller: ipControler,
                    decoration: const InputDecoration(
                      icon: Icon(Icons.router),
                      hintText: '000.000.000.000',
                      labelText: 'Endereço IP do Broker',
                      labelStyle: TextStyle(
                        color: Color.fromRGBO(19, 85, 156, 1),
                      ),
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [LengthLimitingTextInputFormatter(15)],
                  ),
                  const SizedBox(height: 30),
                  TextFormField(
                    controller: portaControler,
                    decoration: const InputDecoration(
                      icon: Icon(Icons.door_front_door),
                      hintText: '1883',
                      labelText: 'Porta do Broker',
                      labelStyle: TextStyle(
                        color: Color.fromRGBO(19, 85, 156, 1),
                      ),
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [LengthLimitingTextInputFormatter(4)],
                  ),
                  const SizedBox(height: 30),
                  Row(
                    children: [
                      const Text('O Broker possui usuário e senha?'),
                      const SizedBox(width: 80),
                      Switch(
                        value: brokerInfo.credenciais,
                        onChanged: (value) =>
                            setState(() => brokerInfo.credenciais = value),
                        activeColor: const Color.fromRGBO(19, 85, 156, 1),
                      ),
                    ],
                  ),
                  if (brokerInfo.credenciais) ...[
                    TextFormField(
                      controller: usuarioControler,
                      decoration: const InputDecoration(
                        icon: Icon(Icons.badge),
                        hintText: 'Usuário',
                        labelText: 'Informe o usuário',
                        labelStyle: TextStyle(
                          color: Color.fromRGBO(19, 85, 156, 1),
                        ),
                      ),
                    ),
                    TextFormField(
                      controller: senhaControler,
                      decoration: const InputDecoration(
                        icon: Icon(Icons.lock),
                        hintText: 'Senha',
                        labelText: 'Digite a senha',
                        labelStyle: TextStyle(
                          color: Color.fromRGBO(19, 85, 156, 1),
                        ),
                      ),
                      obscureText: true,
                    ),
                  ],
                  const SizedBox(height: 80),
                  Center(
                    child: ElevatedButton(
                      onPressed: () {
                        if (brokerInfo.status == 'Conectado') {
                          _disconnect();
                        } else {
                          _connect();
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: brokerInfo.status == 'Conectado'
                            ? Colors.red
                            : const Color.fromRGBO(19, 85, 156, 1),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 30,
                          vertical: 15,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                      child: Text(
                        brokerInfo.status == 'Conectado'
                            ? 'Desconectar do Broker'
                            : 'Conectar ao Broker',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(
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
                    MaterialPageRoute(
                      builder: (context) => const ConectaBroker(),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.assignment, color: Colors.white),
                  onPressed: () => Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const DadosExperimentos(),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.science, color: Colors.white),
                  onPressed: () => Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const Experimento(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _confimacaoLimparDados() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Limpar Dados'),
        content: const Text(
          'Tem certeza que deseja apagar os dados e desconectar do Broker?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Cancelar',
              style: TextStyle(color: Color.fromRGBO(19, 85, 156, 1)),
            ),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                ipControler.clear();
                portaControler.clear();
                usuarioControler.clear();
                senhaControler.clear();
              });
              BrokerInfo.instance.disconnect();
              Navigator.pop(context);
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => const StartScreen()),
              );
            },
            child: const Text(
              'Confirmar',
              style: TextStyle(color: Color.fromRGBO(19, 85, 156, 1)),
            ),
          ),
        ],
      ),
    );
  }
}
