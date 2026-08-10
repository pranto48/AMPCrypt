/*
 * Copyright (c) IT Support BD (https://itsupport.com.bd). All rights reserved.
 * This file is part of AMPCrypt.
 This program is free software but it under the terms of the GNU Affero General Public License.
 * (This project website link: https://ampcrypt.itsupport.com.bd)
 */

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/version_check_service.dart';

class CryptomatorBanners extends StatefulWidget {
  final VoidCallback? onUpdateTap;
  final VoidCallback? onSupportTap;

  const CryptomatorBanners({
    super.key,
    this.onUpdateTap,
    this.onSupportTap,
  });

  @override
  State<CryptomatorBanners> createState() => _CryptomatorBannersState();
}

class _CryptomatorBannersState extends State<CryptomatorBanners> {
  bool _showUpdateBanner = false;
  bool _showSupportBanner = true;

  @override
  void initState() {
    super.initState();
    _checkOnlineUpdates();
  }

  Future<void> _checkOnlineUpdates() async {
    final updateAvailable = await VersionCheckService.isUpdateAvailable();
    if (mounted) {
      setState(() {
        _showUpdateBanner = updateAvailable;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_showUpdateBanner && !_showSupportBanner) {
      return const SizedBox.shrink();
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_showUpdateBanner)
          InkWell(
            onTap: widget.onUpdateTap,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: const Color(0xFFEAB308), // Amber / Gold color matching image
              child: Row(
                children: [
                  const Spacer(),
                  Text(
                    'Update is available from https://ampcrypt.itsupport.com.bd/desktop',
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  const Spacer(),
                  InkWell(
                    onTap: () => setState(() => _showUpdateBanner = false),
                    child: const Icon(
                      Icons.close_rounded,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (_showSupportBanner)
          InkWell(
            onTap: widget.onSupportTap,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: const Color(0xFF388E3C), // Vibrant Green matching image
              child: Row(
                children: [
                  const Spacer(),
                  Text(
                    'Support AMPCrypt.',
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const Spacer(),
                  InkWell(
                    onTap: () => setState(() => _showSupportBanner = false),
                    child: const Icon(
                      Icons.close_rounded,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
