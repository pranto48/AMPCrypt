/*
 * Copyright (c) IT Support BD (https://itsupport.com.bd). All rights reserved.
 * AMPCrypt Transparent Windows ICO Generator
 */

import 'dart:io';
import 'dart:typed_data';

void main() {
  final baseDir = Directory.current.path;
  final appIconDir = '$baseDir/macos/Runner/Assets.xcassets/AppIcon.appiconset';

  final sizes = [16, 32, 64, 128, 256];
  final List<Uint8List> pngBytesList = [];

  for (final size in sizes) {
    final file = File('$appIconDir/app_icon_$size.png');
    if (!file.existsSync()) {
      print('Missing icon file: ${file.path}');
      return;
    }
    pngBytesList.add(file.readAsBytesSync());
  }

  final numImages = sizes.length;
  final headerSize = 6 + (16 * numImages);
  
  int currentOffset = headerSize;
  final List<int> icoBytes = [];

  // 1. Write ICO Header
  icoBytes.addAll([0x00, 0x00]); // Reserved
  icoBytes.addAll([0x01, 0x00]); // Type: ICO
  icoBytes.add(numImages & 0xFF);
  icoBytes.add((numImages >> 8) & 0xFF); // Image Count

  // 2. Write Directory Entries
  for (int i = 0; i < numImages; i++) {
    final size = sizes[i];
    final bytes = pngBytesList[i];
    final bytesSize = bytes.length;

    final widthByte = size == 256 ? 0 : size;
    final heightByte = size == 256 ? 0 : size;

    icoBytes.add(widthByte); // Width
    icoBytes.add(heightByte); // Height
    icoBytes.add(0); // Color palette
    icoBytes.add(0); // Reserved
    icoBytes.addAll([0x01, 0x00]); // Color planes (1)
    icoBytes.addAll([0x20, 0x00]); // Bits per pixel (32)

    // BytesInRes (4 bytes)
    icoBytes.add(bytesSize & 0xFF);
    icoBytes.add((bytesSize >> 8) & 0xFF);
    icoBytes.add((bytesSize >> 16) & 0xFF);
    icoBytes.add((bytesSize >> 24) & 0xFF);

    // ImageOffset (4 bytes)
    icoBytes.add(currentOffset & 0xFF);
    icoBytes.add((currentOffset >> 8) & 0xFF);
    icoBytes.add((currentOffset >> 16) & 0xFF);
    icoBytes.add((currentOffset >> 24) & 0xFF);

    currentOffset += bytesSize;
  }

  // 3. Write PNG Image Data
  for (final bytes in pngBytesList) {
    icoBytes.addAll(bytes);
  }

  final finalIcoData = Uint8List.fromList(icoBytes);

  File('$baseDir/assets/vault_drive.ico').writeAsBytesSync(finalIcoData);
  File('$baseDir/assets/app_icon.ico').writeAsBytesSync(finalIcoData);

  print('Successfully generated clean transparent vault_drive.ico and app_icon.ico (${finalIcoData.length} bytes)');
}
