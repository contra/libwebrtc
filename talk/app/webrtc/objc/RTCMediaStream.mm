/*
 * libjingle
 * Copyright 2013, Google Inc.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 *  1. Redistributions of source code must retain the above copyright notice,
 *     this list of conditions and the following disclaimer.
 *  2. Redistributions in binary form must reproduce the above copyright notice,
 *     this list of conditions and the following disclaimer in the documentation
 *     and/or other materials provided with the distribution.
 *  3. The name of the author may not be used to endorse or promote products
 *     derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR IMPLIED
 * WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO
 * EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 * SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
 * PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS;
 * OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
 * WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
 * OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
 * ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#if !defined(__has_feature) || !__has_feature(objc_arc)
#error "This file requires ARC support."
#endif

#import "RTCMediaStream+Internal.h"
#import "RTCMediaStreamTrack+Internal.h"
#import "RTCAudioTrack+Internal.h"
#import "RTCVideoTrack+Internal.h"

#include "talk/app/webrtc/mediastreaminterface.h"

namespace webrtc {
  class RTCMediaStreamObserver : public ObserverInterface {
    public:
    RTCMediaStreamObserver(RTCMediaStream* stream) { _stream = stream; }

    void OnChanged() override {
      [_stream update];
    }

   private:
    __weak RTCMediaStream* _stream;
  };
}

@implementation RTCMediaStream {
  NSMutableArray* _audioTracks;
  NSMutableArray* _videoTracks;
  rtc::scoped_refptr<webrtc::MediaStreamInterface> _mediaStream;
  rtc::scoped_ptr<webrtc::RTCMediaStreamObserver> _observer;
}

- (NSString*)description {
  return [NSString stringWithFormat:@"[%@:A=%lu:V=%lu]",
                                    [self label],
                                    (unsigned long)[self.audioTracks count],
                                    (unsigned long)[self.videoTracks count]];
}

- (NSArray*)audioTracks {
  return [_audioTracks copy];
}

- (NSArray*)videoTracks {
  return [_videoTracks copy];
}

- (NSString*)label {
  return @(self.mediaStream->label().c_str());
}

- (BOOL)addAudioTrack:(RTCAudioTrack*)track {
  if (self.mediaStream->AddTrack(track.audioTrack)) {
    return YES;
  }
  return NO;
}

- (BOOL)addVideoTrack:(RTCVideoTrack*)track {
  if (self.mediaStream->AddTrack(track.nativeVideoTrack)) {
    return YES;
  }
  return NO;
}

- (BOOL)removeAudioTrack:(RTCAudioTrack*)track {
  NSUInteger index = [_audioTracks indexOfObjectIdenticalTo:track];
  NSAssert(index != NSNotFound,
           @"|removeAudioTrack| called on unexpected RTCAudioTrack");
  if (index != NSNotFound && self.mediaStream->RemoveTrack(track.audioTrack)) {
    return YES;
  }
  return NO;
}

- (BOOL)removeVideoTrack:(RTCVideoTrack*)track {
  NSUInteger index = [_videoTracks indexOfObjectIdenticalTo:track];
  NSAssert(index != NSNotFound,
           @"|removeAudioTrack| called on unexpected RTCVideoTrack");
  if (index != NSNotFound &&
      self.mediaStream->RemoveTrack(track.nativeVideoTrack)) {
    return YES;
  }
  return NO;
}

@end

@implementation RTCMediaStream (Internal)

- (id)initWithMediaStream:
          (rtc::scoped_refptr<webrtc::MediaStreamInterface>)mediaStream {
  if (!mediaStream) {
    NSAssert(NO, @"nil arguments not allowed");
    self = nil;
    return nil;
  }
  if ((self = [super init])) {
    webrtc::AudioTrackVector audio_tracks = mediaStream->GetAudioTracks();
    webrtc::VideoTrackVector video_tracks = mediaStream->GetVideoTracks();

    _audioTracks = [NSMutableArray arrayWithCapacity:audio_tracks.size()];
    _videoTracks = [NSMutableArray arrayWithCapacity:video_tracks.size()];
    _mediaStream = mediaStream;
    _observer.reset(new webrtc::RTCMediaStreamObserver(self));
    _mediaStream->RegisterObserver(_observer.get());

    for (size_t i = 0; i < audio_tracks.size(); ++i) {
      rtc::scoped_refptr<webrtc::AudioTrackInterface> track =
          audio_tracks[i];
      RTCAudioTrack* audioTrack =
          [[RTCAudioTrack alloc] initWithMediaTrack:track];
      [_audioTracks addObject:audioTrack];
    }

    for (size_t i = 0; i < video_tracks.size(); ++i) {
      rtc::scoped_refptr<webrtc::VideoTrackInterface> track =
          video_tracks[i];
      RTCVideoTrack* videoTrack =
          [[RTCVideoTrack alloc] initWithMediaTrack:track];
      [_videoTracks addObject:videoTrack];
    }
  }
  return self;
}

- (void)dealloc {
  _mediaStream->UnregisterObserver(_observer.get());
}

- (rtc::scoped_refptr<webrtc::MediaStreamInterface>)mediaStream {
  return _mediaStream;
}

- (void)update {
  size_t i;
  webrtc::AudioTrackVector native_audio_tracks = _mediaStream->GetAudioTracks();
  webrtc::VideoTrackVector native_video_tracks = _mediaStream->GetVideoTracks();
  std::vector<size_t> removedAudioTrackIndexes;
  std::vector<size_t> removedVideoTrackIndexes;

  // Detect audio tracks removal.
  for (i = 0; i < [_audioTracks count]; i++) {
    RTCAudioTrack* objcTrack = [_audioTracks objectAtIndex:i];
    NSNumber* index;

    if (![self hasNativeAudioTrack:objcTrack]) {
      removedAudioTrackIndexes.push_back(i);
    }
  }

  // Detect video tracks removal.
  for (i = 0; i < [_videoTracks count]; i++) {
    RTCVideoTrack* objcTrack = [_videoTracks objectAtIndex:i];
    NSNumber* index;

    if (![self hasNativeVideoTrack:objcTrack]) {
      removedVideoTrackIndexes.push_back(i);
    }
  }

  // Remove old audio tracks and notify the delegate.
  for (std::vector<size_t>::iterator it = removedAudioTrackIndexes.begin();
    it != removedAudioTrackIndexes.end(); ++it) {
    RTCAudioTrack* objcTrack = [_audioTracks objectAtIndex:*it];

    // Remove the track from the ObjC container.
    [_audioTracks removeObjectAtIndex:*it];

    // Notify the delegate.
    [_delegate OnRemoveAudioTrack:self track:objcTrack];
  }

  // Remove old video tracks and notify the delegate.
  for (std::vector<size_t>::iterator it = removedVideoTrackIndexes.begin();
    it != removedVideoTrackIndexes.end(); ++it) {
    RTCVideoTrack* objcTrack = [_videoTracks objectAtIndex:*it];

    // Remove the track from the ObjC container.
    [_videoTracks removeObjectAtIndex:*it];

    // Notify the delegate.
    [_delegate OnRemoveVideoTrack:self track:objcTrack];
  }

  // Detect audio tracks addition and notify the delegate.
  for (i = 0; i < native_audio_tracks.size(); ++i) {
    rtc::scoped_refptr<webrtc::AudioTrackInterface> nativeTrack =
      native_audio_tracks[i];

    if (![self hasObjcAudioTrack:nativeTrack]) {
      // Create the RTCAudioTrack instance and add it to the ObjC container.
      RTCAudioTrack* objcTrack =
        [[RTCAudioTrack alloc] initWithMediaTrack:nativeTrack];
      [_audioTracks addObject:objcTrack];

      // Notify the delegate.
      [_delegate OnAddAudioTrack:self track:objcTrack];
    }
  }

  // Detect video tracks addition and notify the delegate.
  for (i = 0; i < native_video_tracks.size(); ++i) {
    rtc::scoped_refptr<webrtc::VideoTrackInterface> nativeTrack =
      native_video_tracks[i];

    if (![self hasObjcVideoTrack:nativeTrack]) {
      // Create the RTCVideoTrack instance and add it to the ObjC container.
      RTCVideoTrack* objcTrack =
        [[RTCVideoTrack alloc] initWithMediaTrack:nativeTrack];
      [_videoTracks addObject:objcTrack];

      // Notify the delegate.
      [_delegate OnAddVideoTrack:self track:objcTrack];
    }
  }

  unsigned long num_native_audios = native_audio_tracks.size();
  unsigned long num_native_videos = native_video_tracks.size();
  unsigned long num_objc_audios = (unsigned long)[_audioTracks count];
  unsigned long num_objc_videos = (unsigned long)[_videoTracks count];

  NSAssert(num_native_audios == num_objc_audios,
    @"ObjC audio tracks does not match number of native audio tracks");

  NSAssert(num_native_videos == num_objc_videos,
    @"ObjC video tracks does not match number of native video tracks");
}

- (BOOL)hasNativeAudioTrack:(RTCAudioTrack *)objcTrack {
  webrtc::AudioTrackVector audio_tracks = _mediaStream->GetAudioTracks();

  for (size_t i = 0; i < audio_tracks.size(); ++i) {
    rtc::scoped_refptr<webrtc::AudioTrackInterface> track = audio_tracks[i];

    if (track->id().compare(objcTrack.audioTrack->id()) == 0) {
      return YES;
    }
  }
  return NO;
}

- (BOOL)hasNativeVideoTrack:(RTCVideoTrack *)objcTrack {
  webrtc::VideoTrackVector video_tracks = _mediaStream->GetVideoTracks();

  for (size_t i = 0; i < video_tracks.size(); ++i) {
    rtc::scoped_refptr<webrtc::VideoTrackInterface> track = video_tracks[i];

    if (track->id().compare(objcTrack.nativeVideoTrack->id()) == 0) {
      return YES;
    }
  }
  return NO;
}

- (BOOL)hasObjcAudioTrack:
    (rtc::scoped_refptr<webrtc::AudioTrackInterface>)nativeTrack {
  for (size_t i = 0; i < [_audioTracks count]; i++) {
    RTCAudioTrack* track = [_audioTracks objectAtIndex:i];

    if (track.audioTrack->id().compare(nativeTrack->id()) == 0) {
      return YES;
    }
  }
  return NO;
}

- (BOOL)hasObjcVideoTrack:
    (rtc::scoped_refptr<webrtc::VideoTrackInterface>)nativeTrack {
  for (size_t i = 0; i < [_videoTracks count]; i++) {
    RTCVideoTrack* track = [_videoTracks objectAtIndex:i];

    if (track.nativeVideoTrack->id().compare(nativeTrack->id()) == 0) {
      return YES;
    }
  }
  return NO;
}

@end
