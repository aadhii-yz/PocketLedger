sealed class PrinterConnection {
  const PrinterConnection();
}

final class UsbConnection extends PrinterConnection {
  final String path; // '/dev/usb/lp0' or CUPS queue on Linux, printer name (e.g. 'TVS RP 3230') on Windows
  const UsbConnection(this.path);

  @override
  String toString() => 'USB @ $path';
}

final class TcpConnection extends PrinterConnection {
  final String ip;
  final int port;
  const TcpConnection(this.ip, this.port);

  @override
  String toString() => '$ip:$port';
}
