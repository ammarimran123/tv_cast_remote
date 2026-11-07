class TvDevice {
  final String host;
  String name;
  String model;
  int remotePort;
  int pairingPort;
  int castPort;
  bool supportsRemote;
  bool supportsCast;
  bool paired;
  DateTime? lastConnected;

  /// Transient: seen on the network during the current scan.
  bool online;

  TvDevice({
    required this.host,
    required this.name,
    this.model = '',
    this.remotePort = 6466,
    this.pairingPort = 6467,
    this.castPort = 8009,
    this.supportsRemote = false,
    this.supportsCast = false,
    this.paired = false,
    this.lastConnected,
    this.online = false,
  });

  String get id => host;

  String get displayModel => model.isEmpty ? 'Android TV' : model;

  void mergeFrom(TvDevice other) {
    if (other.name.isNotEmpty && other.name != other.host) name = other.name;
    if (other.model.isNotEmpty) model = other.model;
    if (other.supportsRemote) {
      supportsRemote = true;
      remotePort = other.remotePort;
    }
    if (other.supportsCast) {
      supportsCast = true;
      castPort = other.castPort;
    }
    online = online || other.online;
  }

  Map<String, dynamic> toJson() => {
    'host': host,
    'name': name,
    'model': model,
    'remotePort': remotePort,
    'pairingPort': pairingPort,
    'castPort': castPort,
    'supportsRemote': supportsRemote,
    'supportsCast': supportsCast,
    'paired': paired,
    'lastConnected': lastConnected?.toIso8601String(),
  };

  factory TvDevice.fromJson(Map<String, dynamic> j) => TvDevice(
    host: j['host'] as String,
    name: j['name'] as String? ?? j['host'] as String,
    model: j['model'] as String? ?? '',
    remotePort: j['remotePort'] as int? ?? 6466,
    pairingPort: j['pairingPort'] as int? ?? 6467,
    castPort: j['castPort'] as int? ?? 8009,
    supportsRemote: j['supportsRemote'] as bool? ?? false,
    supportsCast: j['supportsCast'] as bool? ?? false,
    paired: j['paired'] as bool? ?? false,
    lastConnected: DateTime.tryParse(j['lastConnected'] as String? ?? ''),
  );
}
