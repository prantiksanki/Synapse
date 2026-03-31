import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

class CameraPreviewWidget extends StatelessWidget {
  final CameraController controller;
  final Widget? overlay;

  const CameraPreviewWidget({
    super.key,
    required this.controller,
    this.overlay,
  });

  @override
  Widget build(BuildContext context) {
    if (!controller.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // Calculate the scale to fill the available space
        final previewSize = controller.value.previewSize!;
        final previewAspectRatio = previewSize.height / previewSize.width;
        final screenAspectRatio = constraints.maxWidth / constraints.maxHeight;

        double scale;
        if (screenAspectRatio > previewAspectRatio) {
          scale = constraints.maxWidth / previewSize.height;
        } else {
          scale = constraints.maxHeight / previewSize.width;
        }

        return ClipRect(
          child: OverflowBox(
            maxWidth: double.infinity,
            maxHeight: double.infinity,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Camera preview with proper aspect ratio
                Transform.scale(
                  scale: scale,
                  child: Center(
                    child: CameraPreview(controller),
                  ),
                ),
                // Overlay (landmarks, gestures, etc.)
                if (overlay != null)
                  SizedBox(
                    width: constraints.maxWidth,
                    height: constraints.maxHeight,
                    child: overlay,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
