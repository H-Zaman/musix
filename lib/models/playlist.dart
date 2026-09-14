class Playlist {
  final String id;
  String name;
  final List<String> trackFilePaths;

  Playlist({
    required this.id,
    required this.name,
    required this.trackFilePaths,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'trackFilePaths': trackFilePaths,
      };

  factory Playlist.fromJson(Map<String, dynamic> json) => Playlist(
        id: json['id'],
        name: json['name'],
        trackFilePaths: List<String>.from(json['trackFilePaths']),
      );
}
