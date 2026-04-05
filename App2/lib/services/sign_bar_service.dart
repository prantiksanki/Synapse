import '../models/sign_item.dart';

class SignBarService {
  static final List<SignItem> _signs = [
    SignItem(
      id: 'hello',
      label: 'Hello',
      videoPath: 'assets/sign_videos/Hello.gif',
    ),
    SignItem(
      id: 'thank_you',
      label: 'Thank You',
      videoPath: 'assets/sign_videos/thank_you.mp4', // adjust to .gif if needed
    ),
    SignItem(
      id: 'help',
      label: 'Help',
      videoPath: 'assets/sign_videos/help.mp4',
    ),
    SignItem(
      id: 'yes',
      label: 'Yes',
      videoPath: 'assets/sign_videos/yes.mp4',
    ),
    SignItem(
      id: 'no',
      label: 'No',
      videoPath: 'assets/sign_videos/no.mp4',
    ),
    // Add more as needed
  ];

  List<SignItem> getSigns() => _signs;
}