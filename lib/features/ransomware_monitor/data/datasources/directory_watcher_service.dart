import 'dart:async';
import 'dart:io';
import 'package:ampcrypt/features/ransomware_monitor/data/models/sliding_window_features.dart';

/// Represents a logged file system event with metadata.
class FileSystemEventLog {
  final DateTime timestamp;
  final FileSystemEvent event;
  final String path;
  final int fileSize;

  FileSystemEventLog({
    required this.timestamp,
    required this.event,
    required this.path,
    required this.fileSize,
  });
}

/// Service to recursively monitor a directory using native [Directory.watch],
/// buffer events, and calculate sliding window metrics.
class DirectoryWatcherService {
  StreamSubscription<FileSystemEvent>? _subscription;
  final List<FileSystemEventLog> _eventLog = [];
  Timer? _slidingWindowTimer;

  final _featuresController = StreamController<SlidingWindowFeatures>.broadcast();
  Stream<SlidingWindowFeatures> get featuresStream => _featuresController.stream;

  final _statusController = StreamController<String>.broadcast();
  Stream<String> get statusStream => _statusController.stream;

  bool _isWatching = false;
  bool get isWatching => _isWatching;
  String? _watchedPath;
  String? get watchedPath => _watchedPath;

  // Common file extensions that are typically safe
  static const Set<String> _whitelistExtensions = {
    'txt', 'dart', 'yaml', 'lock', 'json', 'png', 'jpg', 'jpeg', 'gif', 'pdf',
    'md', 'git', 'html', 'css', 'js', 'ts', 'xml', 'csv', 'mp3', 'mp4',
    'zip', 'tar', 'gz', 'dmg', 'exe', 'app', 'class', 'gradle', 'properties',
    'iml', 'kt', 'java', 'swift', 'h', 'm', 'cpp', 'c', 'py', 'sh',
    'config', 'log', 'db', 'sqlite', 'svg', 'ico', 'webmanifest',
    'toml', 'ini', 'cfg', 'plist', 'lock'
  };

  /// Starts watching a directory recursively.
  void startWatching(String path) {
    if (_isWatching) {
      stopWatching();
    }

    final dir = Directory(path);
    if (!dir.existsSync()) {
      _statusController.add('Error: Directory does not exist');
      return;
    }

    _watchedPath = path;
    _isWatching = true;
    _eventLog.clear();

    _statusController.add('Monitoring active: $path');

    _subscription = dir.watch(recursive: true).listen(
      (event) {
        final now = DateTime.now();
        final filePath = event.path;
        final fileSize = _getFileSizeSync(filePath);

        _eventLog.add(FileSystemEventLog(
          timestamp: now,
          event: event,
          path: filePath,
          fileSize: fileSize,
        ));
      },
      onError: (error) {
        _statusController.add('Watcher error: $error');
      },
    );

    // Calculate features every 1 second over the last 5-second window
    _slidingWindowTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _processSlidingWindow();
    });
  }

  /// Stops the active watcher.
  void stopWatching() {
    _subscription?.cancel();
    _subscription = null;
    _slidingWindowTimer?.cancel();
    _slidingWindowTimer = null;
    _isWatching = false;
    _watchedPath = null;
    _eventLog.clear();
    _statusController.add('Monitoring stopped');
  }

  /// Calculates sliding window features and fires the event.
  void _processSlidingWindow() {
    final now = DateTime.now();
    final windowStart = now.subtract(const Duration(seconds: 5));

    // Remove logs older than 10 seconds to conserve memory
    _eventLog.removeWhere((log) => log.timestamp.isBefore(now.subtract(const Duration(seconds: 10))));

    // Filter events in the current 5-second window
    final windowEvents = _eventLog.where((log) => log.timestamp.isAfter(windowStart)).toList();

    int createCount = 0;
    int modifyCount = 0;
    int deleteCount = 0;
    int moveCount = 0;
    int suspiciousExtensionCount = 0;
    double totalSize = 0.0;
    int sizeCount = 0;

    for (final log in windowEvents) {
      final type = log.event.type;
      if (type == FileSystemEvent.create) {
        createCount++;
      } else if (type == FileSystemEvent.modify) {
        modifyCount++;
      } else if (type == FileSystemEvent.delete) {
        deleteCount++;
      } else if (type == FileSystemEvent.move) {
        moveCount++;
      }

      // Check file extension
      final ext = _getExtension(log.path);
      if (ext.isNotEmpty && !_whitelistExtensions.contains(ext)) {
        suspiciousExtensionCount++;
      }

      if (log.fileSize > 0) {
        totalSize += log.fileSize / 1024.0; // convert to KB
        sizeCount++;
      }
    }

    final double writeRate = (createCount + modifyCount) / 5.0;
    final double deleteRate = deleteCount / 5.0;
    final double renameRate = moveCount / 5.0;
    final double extensionEntropy = windowEvents.isEmpty ? 0.0 : suspiciousExtensionCount / windowEvents.length;
    final double avgSizeKB = sizeCount == 0 ? 0.0 : totalSize / sizeCount;

    final features = SlidingWindowFeatures(
      writeRate: writeRate,
      deleteRate: deleteRate,
      renameRate: renameRate,
      extensionEntropy: extensionEntropy,
      sizeDifference: avgSizeKB,
    );

    _featuresController.add(features);
  }

  int _getFileSizeSync(String path) {
    try {
      final file = File(path);
      if (file.existsSync()) {
        return file.lengthSync();
      }
    } catch (_) {}
    return 0;
  }

  String _getExtension(String path) {
    final lastDot = path.lastIndexOf('.');
    if (lastDot == -1 || lastDot == path.length - 1) return '';
    final separator = Platform.isWindows ? '\\' : '/';
    final lastSeparator = path.lastIndexOf(separator);
    if (lastSeparator > lastDot) return '';
    return path.substring(lastDot + 1).toLowerCase();
  }

  void dispose() {
    stopWatching();
    _featuresController.close();
    _statusController.close();
  }
}
