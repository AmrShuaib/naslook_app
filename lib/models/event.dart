class Event {
  final String id;
  final String name;
  final String description;
  final String location;
  final bool isPrivate;
  final bool showOnMapIfPrivate;
  final bool allowDirectPurchaseIfPrivate;
  final bool allowDirectJoinIfPrivate;

  Event({
    required this.id,
    required this.name,
    required this.description,
    required this.location,
    required this.isPrivate,
    required this.showOnMapIfPrivate,
    required this.allowDirectPurchaseIfPrivate,
    required this.allowDirectJoinIfPrivate,
  });
}
