import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'broker.dart';
import 'experimento.dart';

class ExperimentoData {
  static final ExperimentoData _instance = ExperimentoData._internal();
  factory ExperimentoData() => _instance;
  ExperimentoData._internal();
  Map<String, String> valores = {
    'observadorKe': "",
    'reguladorK': "",
    'nx': "",
    'nu': "",
    'referencia': "",
  };
}

class DadosExperimentos extends StatefulWidget {
  const DadosExperimentos({super.key});
  @override
  State<DadosExperimentos> createState() => _DadosExperimentosState();
}

class _DadosExperimentosState extends State<DadosExperimentos> {
  final TextEditingController observadorKeController = TextEditingController();
  final TextEditingController reguladorKController = TextEditingController();
  final TextEditingController nxController = TextEditingController();
  final TextEditingController nuController = TextEditingController();
  final TextEditingController referenciaController = TextEditingController();

  void mostrarMensagem(BuildContext context, String titulo, String conteudo) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(titulo,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 15),
              Flexible(
                child: SingleChildScrollView(
                  child: Text(
                    conteudo,
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Fechar'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    final dados = ExperimentoData();
    observadorKeController.text = dados.valores['observadorKe']!;
    reguladorKController.text = dados.valores['reguladorK']!;
    nxController.text = dados.valores['nx']!;
    nuController.text = dados.valores['nu']!;
    referenciaController.text = dados.valores['referencia']!;
    void salvarValor(String chave, String valor) =>
        dados.valores[chave] = valor;
    observadorKeController.addListener(
        () => salvarValor('observadorKe', observadorKeController.text));
    reguladorKController.addListener(
        () => salvarValor('reguladorK', reguladorKController.text));
    nxController.addListener(() => salvarValor('nx', nxController.text));
    nuController.addListener(() => salvarValor('nu', nuController.text));
    referenciaController.addListener(
        () => salvarValor('referencia', referenciaController.text));
  }

  void mostrarErro(BuildContext context, String mensagem) {
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

  Future<void> enviarDados(BuildContext context) async {
    final connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult == ConnectivityResult.none) {
      mostrarErro(context, 'Sem conexão com a Internet!');
      return;
    }
    final BrokerInfo brokerInfo = BrokerInfo();
    if (brokerInfo.credenciais &&
        (brokerInfo.usuario.isEmpty || brokerInfo.senha.isEmpty)) {
      mostrarErro(context, 'Usuário ou senha do Broker não configurados!');
      return;
    }
    if (observadorKeController.text.isEmpty ||
        reguladorKController.text.isEmpty ||
        nxController.text.isEmpty ||
        nuController.text.isEmpty) {
      mostrarErro(context, 'Preencha todos os campos antes de enviar!');
      return;
    }
    final client = MqttServerClient(brokerInfo.ip, 'flutter_client');
    client.port = brokerInfo.porta;
    client.keepAlivePeriod = 20;
    client.secure = false;
    if (brokerInfo.credenciais) {
      client.setProtocolV311();
      client.logging(on: false);
      client.connectionMessage = MqttConnectMessage()
          .withClientIdentifier('flutter_client')
          .authenticateAs(brokerInfo.usuario, brokerInfo.senha)
          .startClean();
    }
    try {
      await client.connect();
      if (client.connectionStatus == null ||
          client.connectionStatus!.state != MqttConnectionState.connected) {
        mostrarErro(context, 'Não foi possível conectar ao Broker!');
        return;
      }
      final Map<String, TextEditingController> campos = {
        'observadorKe': observadorKeController,
        'reguladorK': reguladorKController,
        'nx': nxController,
        'nu': nuController,
        'referencia': referenciaController,
      };
      for (var entry in campos.entries) {
        final builder = MqttClientPayloadBuilder();
        builder.addString(entry.value.text.trim());
        client.publishMessage(entry.key, MqttQos.atMostOnce, builder.payload!);
      }
      
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Sucesso!'),
          content: const Text('Dados enviados com sucesso para o Broker!'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context); 
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const Experimento(),
                  ),
                );
              },
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (e) {
      mostrarErro(context, 'Erro ao conectar ao Broker: $e');
    } finally {
      client.unsubscribe('#');
      client.disconnect();
    }
  }

  @override
  Widget build(BuildContext context) {
    final brokerInfo = BrokerInfo();
    return Scaffold(
      appBar: AppBar(
        leading: Builder(builder: (context) {
          return IconButton(
            onPressed: () {
              Scaffold.of(context).openDrawer();
            },
            icon: const Icon(Icons.menu, color: Colors.white),
          );
        }),
        title: const Text('Dados do Experimento',
            style:
                TextStyle(fontSize: 25, fontWeight: FontWeight.bold, color: Colors.white)),
        centerTitle: true,
        backgroundColor: const Color.fromRGBO(19, 85, 156, 1),
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
                        style: const TextStyle(fontSize: 14, color: Colors.white),
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
                  const SizedBox(height: 25),
                  campoDeTexto(
                      'Observador Ke',
                      observadorKeController,
                      Icons.visibility,
                      () => mostrarMensagem(
                          context,
                          'Observador de Estados',
                          'Passo a passo para encontrar o observador de estados:\n'
                              '\n'
                              '\u2022 Equação dinâmica do erro:\n $\epsilon(t)=(A-K_{e}C)\epsilon(t)\n'
                              '\n'
                              '\u2022 Alocação do polo em $s=-1:\n$ $|sI-(A-K_{e}C)|=s+1=0\n'
                              '\n'
                              '\u2022 Parâmetros do tanque (Eq.6):\n $A=-0.006 | C=1\n'
                              '\n'
                              'Substitua os valores na equação dinâmica do erro e encontrará o valor de Ke'
                              '\n')),
                  const SizedBox(height: 15),
                  campoDeTexto(
                      'Regulador K',
                      reguladorKController,
                      Icons.tune,
                      () => mostrarMensagem(
                          context,
                          'Regulador K',
                          'Passo a passo para encontrar o regulador por realimentação:\n'
                              '\n'
                              '\u2022 Lei de controle:\n $u(t)=-Kx(t)+N_{u}r_{ss}\n'
                              '\n'
                              '\u2022 Alocação do polo em $s=-0.1:\n$ $|sI-(A-BK)|=s+0.1=0\n'
                              '\n'
                              '\u2022 Parâmetros do sistema:\n $A=-0.006$ | $B=0.002\n'
                              '\n'
                              'Substitua os valores na equação de alocação de polo e encontrará o valor de K'
                              '\n')),
                  const SizedBox(height: 15),
                  campoDeTexto(
                      'N° de estados',
                      nxController,
                      Icons.analytics,
                      () => mostrarMensagem(
                          context,
                          'Número de Estados Nx',
                          'Passo a passo para determinar da ordem do sistema:\n'
                              '\n'
                              '\u2022 Modelo do tanque (Eq.6):\n $dh/dt=-0.006h+0.002u\n'
                              '\n'
                              '\u2022 Representação em espaço de estados:\n $\dot{x}=[-0.006]x+[0.002]u\n'
                              '\n'
                              '\n'
                              'Substitua os valores na equação de espaços de estados e encontrará o valor de Nx'
                              '\n')),
                  const SizedBox(height: 15),
                  campoDeTexto(
                      'N° de entradas',
                      nuController,
                      Icons.list_alt,
                      () => mostrarMensagem(
                          context,
                          'Número de Entradas Nu',
                          'Passo a passo para identificar as entradas:\n'
                              '\n'
                              '\u2022 Sistema SISO (Single-Input Single-Output)\n'
                              '\n'
                              '\u2022 Matriz de entrada B:\n $B=[0.002](1x1)\n'
                              '\n'
                              'Número de entradas de controle é determinado pela matriz de entrada\n'
                              '\n')),
                  const SizedBox(height: 15),
                  campoDeTexto(
                      'Referência',
                      referenciaController,
                      Icons.flag,
                      () => mostrarMensagem(context, 'Referência',
                          '\u2022 Insira a altura desejada para o tanque\n'
                              '\n'
                              '\u2022 Valor sugerido no laboratório: 10.0 cm\n'
                              '\n')),
                  const SizedBox(height: 150),
                  Center(
                    child: ElevatedButton(
                      onPressed: () => enviarDados(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color.fromRGBO(19, 85, 156, 1),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 30, vertical: 15),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20)),
                      ),
                      child: const Text('Enviar dados do Experimento',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white)),
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
                  onPressed: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                          builder: (BuildContext context) =>
                              const ConectaBroker()),
                    );
                  },
                ),
                const IconButton(
                  icon: Icon(Icons.assignment, color: Colors.white),
                  onPressed: null, 
                ),
                IconButton(
                  icon: const Icon(Icons.science, color: Colors.white),
                  onPressed: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                          builder: (BuildContext context) =>
                              const Experimento()),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget campoDeTexto(String label, TextEditingController controller,
      IconData icon, VoidCallback onInfoPress) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20.0),
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(
          icon: Icon(icon, color: const Color.fromRGBO(19, 85, 156, 1)),
          labelText: label,
          labelStyle: const TextStyle(color: Color.fromRGBO(19, 85, 156, 1)),
          suffixIcon: IconButton(
            onPressed: onInfoPress,
            icon: const Icon(Icons.help, color: Color.fromRGBO(19, 85, 156, 1)),
          ),
        ),
        keyboardType: TextInputType.number,
        inputFormatters: [LengthLimitingTextInputFormatter(15)],
      ),
    );
  }
}
