class AppSettings {
  AppSettings({
    this.endpoint = 'https://api.openai.com/v1',
    this.apiKey = '',
    this.model = 'gpt-4o',
    this.systemPrompt = 'You are a helpful, knowledgeable assistant. Respond concisely and accurately.',
    this.maxTokens = 4096,
    this.temperature = 0.7,
    this.sidebarVisibleInTouchMode = true,
    this.sidebarVisibleInVisionMode = true,
    this.sidebarAutoHideVoice = false,
    this.useSystemColors = true,
    this.onboardingCompleted = false,
  });

  String endpoint;
  String apiKey;
  String model;
  String systemPrompt;
  int maxTokens;
  double temperature;
  bool sidebarVisibleInTouchMode;
  bool sidebarVisibleInVisionMode;
  bool sidebarAutoHideVoice;
  bool useSystemColors;
  bool onboardingCompleted;

  Map<String, dynamic> toJson() => {
        'endpoint': endpoint,
        'apiKey': apiKey,
        'model': model,
        'systemPrompt': systemPrompt,
        'maxTokens': maxTokens,
        'temperature': temperature,
        'sidebarVisibleInTouchMode': sidebarVisibleInTouchMode,
        'sidebarVisibleInVisionMode': sidebarVisibleInVisionMode,
        'sidebarAutoHideVoice': sidebarAutoHideVoice,
        'useSystemColors': useSystemColors,
        'onboardingCompleted': onboardingCompleted,
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        endpoint: json['endpoint'] as String? ?? 'https://api.openai.com/v1',
        apiKey: json['apiKey'] as String? ?? '',
        model: json['model'] as String? ?? 'gpt-4o',
        systemPrompt: json['systemPrompt'] as String? ?? 'You are a helpful, knowledgeable assistant. Respond concisely and accurately.',
        maxTokens: json['maxTokens'] as int? ?? 4096,
        temperature: (json['temperature'] as num?)?.toDouble() ?? 0.7,
        sidebarVisibleInTouchMode: json['sidebarVisibleInTouchMode'] as bool? ?? true,
        sidebarVisibleInVisionMode: json['sidebarVisibleInVisionMode'] as bool? ?? true,
        sidebarAutoHideVoice: json['sidebarAutoHideVoice'] as bool? ?? false,
        useSystemColors: json['useSystemColors'] as bool? ?? true,
        onboardingCompleted: json['onboardingCompleted'] as bool? ?? false,
      );
}
