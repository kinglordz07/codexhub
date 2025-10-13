// WebRTC manager for flutter_webrtc + Supabase signaling
// Place this file in: lib/services/webrtc_manager.dart

import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// WebRTCManager handles creating peer connections, local media, and
/// exchanging SDP + ICE candidates via Supabase `calls` table using CallService.
class WebRTCManager {
  final SupabaseClient _supabase = Supabase.instance.client;

  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  final Map<String, dynamic> _iceServers = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
    ]
  };

  StreamSubscription<List<Map<String, dynamic>>>? _callStreamSub;

  // Call state
  String? callId;

  // UI hooks / callbacks
  void Function(MediaStream? localStream)? onLocalStream;
  void Function(MediaStream? remoteStream)? onRemoteStream;
  void Function()? onCallEnded;

  WebRTCManager({this.onLocalStream, this.onRemoteStream, this.onCallEnded});

  /// Create or get local media (audio/video based on callType)
  Future<MediaStream> createLocalStream({required bool video}) async {
    final Map<String, dynamic> mediaConstraints = {
      'audio': true,
      'video': video
          ? {
              'facingMode': 'user',
              'width': {'ideal': 1280},
              'height': {'ideal': 720},
            }
          : false,
    };

    _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
    onLocalStream?.call(_localStream);
    return _localStream!;
  }

  /// Initialize a peer connection and set handlers
  Future<RTCPeerConnection> _createPeerConnection() async {
    final config = _iceServers;
    final Map<String, dynamic> constraints = {
      'mandatory': {},
      'optional': [
        {'DtlsSrtpKeyAgreement': true},
      ],
    };

    _pc = await createPeerConnection(config, constraints);

    // Send any ICE candidates to supabase (append to ice_candidates jsonb)
    _pc!.onIceCandidate = (RTCIceCandidate candidate) async {
      if (callId == null) return;
      final candidateMap = {
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex
      };

      // Append candidate to ice_candidates array
      final existing = await _supabase
          .from('calls')
          .select('ice_candidates')
          .eq('id', callId!)
          .single();

      List<dynamic> list = [];
      if (existing['ice_candidates'] != null) {
        list = List<dynamic>.from(existing['ice_candidates']);
      }
      list.add(candidateMap);
      await _supabase.from('calls').update({'ice_candidates': list}).eq('id', callId!);
    };

    _pc!.onIceConnectionState = (state) {
      // you can observe connection state
      // print('ICE state: $state');
    };

    _pc!.onAddStream = (MediaStream stream) {
      onRemoteStream?.call(stream);
    };

    return _pc!;
  }

  /// Caller flow: start call -> create local stream -> create offer -> save offer to calls table
  Future<String> startCallAndCreateOffer({required String receiverId, required bool video}) async {
    // 1) create call record
    final createdCall = await _supabase.from('calls').insert({
      'caller_id': _supabase.auth.currentUser?.id,
      'receiver_id': receiverId,
      'status': 'ringing',
      'call_type': video ? 'video' : 'audio',
      'ice_candidates': [],
      'created_at': DateTime.now().toIso8601String(),
    }).select().single();

    callId = createdCall['id'] as String;

    // 2) create local stream
    await createLocalStream(video: video);

    // 3) create peer connection and add local stream
    await _createPeerConnection();
    if (_localStream != null) _pc!.addStream(_localStream!);

    // 4) create offer
    final offer = await _pc!.createOffer({'offerToReceiveVideo': video ? 1 : 0});
    await _pc!.setLocalDescription(offer);

    // 5) save offer SDP into calls table
    await _supabase.from('calls').update({'sdp_offer': offer.sdp}).eq('id', callId!);

    // 6) listen for answer and remote ICE candidates
    _listenForAnswerAndCandidates();

    return callId!;
  }

  /// Receiver flow: join call -> create local stream -> set remote offer -> create answer
  Future<void> joinCallAndAnswer({required String callIdArg, required bool video}) async {
    callId = callIdArg;

    // 1) get call row
    final callRow = await _supabase.from('calls').select().eq('id', callId!).single();

    final offerSdp = callRow['sdp_offer'] as String?;
    if (offerSdp == null) throw Exception('Offer not available yet');

    // 2) create local stream
    await createLocalStream(video: video);

    // 3) create peer connection and add local stream
    await _createPeerConnection();
    if (_localStream != null) _pc!.addStream(_localStream!);

    // 4) set remote description from offer
    await _pc!.setRemoteDescription(RTCSessionDescription(offerSdp, 'offer'));

    // 5) create answer
    final answer = await _pc!.createAnswer({'offerToReceiveVideo': video ? 1 : 0});
    await _pc!.setLocalDescription(answer);

    // 6) save answer to calls table and mark accepted
    await _supabase.from('calls').update({'sdp_answer': answer.sdp, 'status': 'accepted'}).eq('id', callId!);

    // 7) listen for remote ICE candidates
    _listenForAnswerAndCandidates();
  }

  void _listenForAnswerAndCandidates() {
    if (callId == null) return;

    // Subscribe to changes for this call row
    _callStreamSub = _supabase
        .from('calls')
        .stream(primaryKey: ['id'])
        .eq('id', callId!)
        .listen((rows) async {
      if (rows.isEmpty) return;
      final row = rows.first;

      // If answer exists and remote description not set yet
      final sdpAnswer = row['sdp_answer'] as String?;
      if (sdpAnswer != null) {
        final desc = RTCSessionDescription(sdpAnswer, 'answer');
        final currentRemote = await _pc?.getRemoteDescription();
        if (currentRemote == null || currentRemote.sdp != sdpAnswer) {
          await _pc?.setRemoteDescription(desc);
        }
      }

      // Process ice_candidates array
      final ice = row['ice_candidates'];
      if (ice != null) {
        final List<dynamic> list = List<dynamic>.from(ice);
        for (final c in list) {
          // Each candidate is a map with candidate, sdpMid, sdpMLineIndex
          try {
            final candidate = RTCIceCandidate(c['candidate'], c['sdpMid'], c['sdpMLineIndex']);
            await _pc?.addCandidate(candidate);
          } catch (e) {
            // ignore duplicates or parsing errors
          }
        }
      }
    });
  }

  /// Ends the call: updates status and cleans up
  Future<void> endCall({String status = 'ended'}) async {
    if (callId != null) {
      await _supabase.from('calls').update({'status': status}).eq('id', callId!);
    }

    _disposePeer();
    onCallEnded?.call();
  }

  void _disposePeer() {
    try {
      _callStreamSub?.cancel();
    } catch (_) {}
    try {
      _pc?.close();
    } catch (_) {}
    try {
      _localStream?.getTracks().forEach((t) => t.stop());
    } catch (_) {}

    _pc = null;
    _localStream = null;
    callId = null;
  }

  /// Manually push an ICE candidate (if you want to add progressively)
  Future<void> pushLocalIceCandidate(RTCIceCandidate candidate) async {
    if (callId == null) return;
    final existing = await _supabase.from('calls').select('ice_candidates').eq('id', callId!).single();
    List<dynamic> list = [];
    if (existing['ice_candidates'] != null) {
      list = List<dynamic>.from(existing['ice_candidates']);
    }
    list.add({
      'candidate': candidate.candidate,
      'sdpMid': candidate.sdpMid,
      'sdpMLineIndex': candidate.sdpMLineIndex,
    });
    await _supabase.from('calls').update({'ice_candidates': list}).eq('id', callId!);
  }
}
