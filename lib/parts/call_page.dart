import 'package:flutter/material.dart';
import 'package:zego_uikit_prebuilt_call/zego_uikit_prebuilt_call.dart';

class CallPage extends StatelessWidget {
  final String userID;
  final String userName;
  final String callID;
  final String callType; // 'video' or 'audio'

  const CallPage({
    super.key,
    required this.userID,
    required this.userName,
    required this.callID,
    required this.callType,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ZegoUIKitPrebuiltCall(
        appID: 265396811, // Your AppID
        appSign: "b37d3fa967273d4e4ce4c7623ab3708f15fcce5707dfbe00a02663dd1e40f5ad", // Your AppSign
        userID: userID,
        userName: userName,
        callID: callID,
        config: callType == 'video'
            ? (ZegoUIKitPrebuiltCallConfig.oneOnOneVideoCall()
              ..turnOnCameraWhenJoining = false
              ..turnOnMicrophoneWhenJoining = true
            )
            : (ZegoUIKitPrebuiltCallConfig.oneOnOneVoiceCall()
              ..turnOnMicrophoneWhenJoining = true
            ),
      ),
    );
  }
}
