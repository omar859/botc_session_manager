import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import '../providers/game_provider.dart';

class ScriptViewer extends StatelessWidget {
  const ScriptViewer({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<GameProvider>();
    final isHost = provider.isHost;
    List<String> urls = [];

    if (isHost) {
      final room = provider.room;
      if (room != null) {
        urls = room.scriptImagePaths
            .map((f) =>
                'http://${provider.hostIp}:${provider.hostPort}/script/$f')
            .toList();
      }
    } else {
      urls = provider.scriptImageUrls;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(urls.isEmpty ? 'Script' : 'Script (${urls.length})'),
      ),
      backgroundColor: Colors.black,
      body: urls.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No script images have been uploaded for this game yet.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 15),
                ),
              ),
            )
          : PhotoViewGallery.builder(
              itemCount: urls.length,
              builder: (context, index) => PhotoViewGalleryPageOptions(
                imageProvider: NetworkImage(urls[index]),
                minScale: PhotoViewComputedScale.contained,
                maxScale: PhotoViewComputedScale.covered * 3,
                heroAttributes: PhotoViewHeroAttributes(tag: urls[index]),
              ),
              scrollPhysics: const BouncingScrollPhysics(),
              backgroundDecoration: const BoxDecoration(color: Colors.black),
              loadingBuilder: (context, event) => const Center(
                child: CircularProgressIndicator(),
              ),
              pageController: PageController(),
            ),
    );
  }
}
