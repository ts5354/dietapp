import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final deviceTimezoneProvider =
    Provider<DeviceTimezone>((ref) => const PlatformDeviceTimezone());

abstract interface class DeviceTimezone {
  Future<String> currentIdentifier();
}

class PlatformDeviceTimezone implements DeviceTimezone {
  const PlatformDeviceTimezone();

  @override
  Future<String> currentIdentifier() async {
    final identifier = (await FlutterTimezone.getLocalTimezone()).identifier;
    if (identifier.trim().isEmpty) {
      throw const TimezoneLookupException();
    }
    return identifier;
  }
}

class TimezoneLookupException implements Exception {
  const TimezoneLookupException([this.cause]);
  final Object? cause;
}
