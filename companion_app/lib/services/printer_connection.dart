sealed class PrinterConnection {
  const PrinterConnection();
}

final class UsbConnection extends PrinterConnection {
  final String path; // '/dev/usb/lp0' on Linux, 'USB001' on Windows
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
