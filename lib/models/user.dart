class User {
  final String id;
  final String name;
  final String headline;
  final String avatarUrl;
  final bool showOnMap;
  final LocationAccuracy locationAccuracy;
  final String? customLocation;

  User({
    required this.id,
    required this.name,
    required this.headline,
    required this.avatarUrl,
    required this.showOnMap,
    required this.locationAccuracy,
    this.customLocation,
  });
}

enum LocationAccuracy { exact, approximate, cityOnly }
