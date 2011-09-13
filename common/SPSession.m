//
//  SPSession.m
//  CocoaLibSpotify
//
//  Created by Daniel Kennett on 2/14/11.
/*
Copyright (c) 2011, Spotify AB
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:
    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.
    * Neither the name of Spotify AB nor the names of its contributors may 
      be used to endorse or promote products derived from this software 
      without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL SPOTIFY AB BE LIABLE FOR ANY DIRECT, INDIRECT,
INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT 
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, 
OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

#import "SPSession.h"
#import "SPErrorExtensions.h"
#import "SPTrack.h"
#import "SPPlaylistContainer.h"
#import "SPUser.h"
#import "SPAlbum.h"
#import "SPArtist.h"
#import "SPPlaylist.h"
#import "SPPlaylistFolder.h"
#import "SPURLExtensions.h"
#import "SPSearch.h"
#import "SPImage.h"
#import "SPPostTracksToInboxOperation.h"
#import "SPPlaylistContainerInternal.h"
#import "SPPlaylistFolderInternal.h"

@interface SPSession ()

@property (readwrite, retain) SPUser *user;
@property (readwrite, retain) NSArray *friends;
@property (readwrite, retain) NSLocale *locale;

@property (readonly, retain) NSMutableDictionary *playlistCache;

@property (readwrite, retain) SPPlaylist *inboxPlaylist;
@property (readwrite, retain) SPPlaylist *starredPlaylist;
@property (readwrite, retain) SPPlaylistContainer *userPlaylists;

@end

#pragma mark Session Callbacks

/* ------------------------  BEGIN SESSION CALLBACKS  ---------------------- */
/**
 * This callback is called when the user was logged in, but the connection to
 * Spotify was dropped for some reason.
 */
static void connection_error(sp_session *session, sp_error error) {
	SPSession *sess = (SPSession *)sp_session_userdata(session);
	
    [sess willChangeValueForKey:@"connectionState"];
    [sess didChangeValueForKey:@"connectionState"]; 
    
    SEL selector = @selector(session:didEncounterNetworkError:);
    
    if ([[sess delegate] respondsToSelector:selector]) {
        
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        [[sess delegate] performSelector:selector
                              withObject:sess
                              withObject:[NSError spotifyErrorWithCode:error]];
        [pool drain];
    }
    
}

/**
 * This callback is called when an attempt to login has succeeded or failed.
 */
static void logged_in(sp_session *session, sp_error error) {
	SPSession *sess = (SPSession *)sp_session_userdata(session);
	
	if (error != SP_ERROR_OK) {
    
		SEL selector = @selector(session:didFailToLoginWithError:);
        
        if ([[sess delegate] respondsToSelector:selector]) {
            
            NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
            [[sess delegate] performSelector:selector
                                  withObject:sess
                                  withObject:[NSError spotifyErrorWithCode:error]];
            [pool drain];
			return;
        }
    }
    
    [sess willChangeValueForKey:@"connectionState"];
    [sess didChangeValueForKey:@"connectionState"];
    
	// XXX DEBUG Let us print the nice message...
	sp_user *me = sp_session_user(session);
	const char *my_name = (sp_user_is_loaded(me) ?
                           sp_user_display_name(me) :
                           sp_user_canonical_name(me));
	NSLog(@"Logged in as user %s", my_name);
    
	SEL selector = @selector(sessionDidLoginSuccessfully:);
    
    if ([[sess delegate] respondsToSelector:selector]) {
        
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        [[sess delegate] performSelector:selector
                              withObject:sess];
        [pool drain];
    }
    
}

/**
 * This callback is called when the session has logged out of Spotify.
 *
 * @sa sp_session_callbacks#logged_out
 */
static void logged_out(sp_session *session) {
	SPSession *sess = (SPSession *)sp_session_userdata(session);
    
    [sess willChangeValueForKey:@"connectionState"];
    [sess didChangeValueForKey:@"connectionState"];
    
    SEL selector = @selector(sessionDidLogOut:);
    
    if ([[sess delegate] respondsToSelector:selector]) {
        
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        [[sess delegate] performSelector:selector
                              withObject:sess];
        [pool drain];
    }
    
}

/**
 * Called when processing needs to take place on the main thread.
 *
 * You need to call sp_session_process_events() in the main thread to get
 * libspotify to do more work. Failure to do so may cause request timeouts,
 * or a lost connection.
 *
 * The most straight forward way to do this is using Unix signals. We use
 * SIGIO. signal(7) in Linux says "I/O now possible" which sounds reasonable.
 *
 * @param[in]  session    Session
 *
 * @note This function is called from an internal session thread - you need
 * to have proper synchronization!
 */
static void notify_main_thread(sp_session *session) {
    
    SPSession *sess = (SPSession *)sp_session_userdata(session);
    
	@synchronized (sess) {
		
		SEL selector = @selector(prodSession);
		
		if ([sess respondsToSelector:selector]) {
			[sess performSelectorOnMainThread:selector
								   withObject:nil
								waitUntilDone:NO];
		}
	}
}

/**
 * This callback is called for log messages.
 */
static void log_message(sp_session *session, const char *data) {
	SPSession *sess = (SPSession *)sp_session_userdata(session);
	
    SEL selector = @selector(session:didLogMessage:);
    
    if ([[sess delegate] respondsToSelector:selector]) {
        
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        [[sess delegate] performSelector:selector
                              withObject:sess
                              withObject:[NSString stringWithUTF8String:data]];
        [pool drain];
    }
    
}

/**
 * Callback called when libspotify has new metadata available
 *
 * If you have metadata cached outside of libspotify, you should purge
 * your caches and fetch new versions.
 */
static void metadata_updated(sp_session *session) {
	SPSession *sess = (SPSession *)sp_session_userdata(session);
	
    SEL selector = @selector(sessionDidChangeMetadata:);
    
    if ([[sess delegate] respondsToSelector:selector]) {
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        [[sess delegate] performSelector:selector
                              withObject:sess];
        [pool drain];
    }
    
}

/**
 * Called when the access point wants to display a message to the user
 *
 * In the desktop client, these are shown in a blueish toolbar just below the
 * search box.
 *
 * @param[in]  session    Session
 * @param[in]  message    String in UTF-8 format.
 */
static void message_to_user(sp_session *session, const char *msg) {
	SPSession *sess = (SPSession *)sp_session_userdata(session);
    
	SEL selector = @selector(session:recievedMessageForUser:);
    
    if ([[sess delegate] respondsToSelector:selector]) {
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        [[sess delegate] performSelector:selector
                              withObject:sess
                              withObject:[NSString stringWithUTF8String:msg]];
        [pool drain];
    }
    
}


/**
 * Called when there is decompressed audio data available.
 *
 * @param[in]  session    Session
 * @param[in]  format     Audio format descriptor sp_audioformat
 * @param[in]  frames     Points to raw PCM data as described by \p format
 * @param[in]  num_frames Number of available samples in \p frames.
 *                        If this is 0, a discontinuity has occured (such as after a seek). The application
 *                        should flush its audio fifos, etc.
 *
 * @return                Number of frames consumed.
 *                        This value can be used to rate limit the output from the library if your
 *                        output buffers are saturated. The library will retry delivery in about 100ms.
 *
 * @note This function is called from an internal session thread - you need to have proper synchronization!
 *
 * @note This function must never block. If your output buffers are full you must return 0 to signal
 *       that the library should retry delivery in a short while.
 */
static int music_delivery(sp_session *session, const sp_audioformat *format, const void *frames, int num_frames) {
	
	SPSession *sess = (SPSession *)sp_session_userdata(session);
	
	if ([[sess playbackDelegate] respondsToSelector:@selector(session:shouldDeliverAudioFrames:ofCount:format:)]) {
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        int framesConsumed = (int)[(id <SPSessionPlaybackDelegate>)[sess playbackDelegate] session:sess
																		  shouldDeliverAudioFrames:frames
																						   ofCount:num_frames
																							format:format]; 
        [pool drain];
		return framesConsumed;
    }
	
	return num_frames;
}

/**
 * Music has been paused because only one account may play music at the same time.
 *
 * @param[in]  session    Session
 */
static void play_token_lost(sp_session *session) {
	SPSession *sess = (SPSession *)sp_session_userdata(session);
	
	[sess setPlaying:NO];
	
    SEL selector = @selector(sessionDidLosePlayToken:);
    
    if ([[sess playbackDelegate] respondsToSelector:selector]) {
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        [[sess playbackDelegate] performSelector:selector
									  withObject:sess];
        [pool drain];
    }
    
}

/**
 * End of track.
 * Called when the currently played track has reached its end.
 *
 * @note This function is invoked from the same internal thread
 * as the music delivery callback
 *
 * @param[in]  session    Session
 */
static void end_of_track(sp_session *session) {
	SPSession *sess = (SPSession *)sp_session_userdata(session);
	
    SEL selector = @selector(sessionDidEndPlayback:);
    
    if ([[sess playbackDelegate] respondsToSelector:selector]) {
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        [(NSObject *)[sess playbackDelegate] performSelectorOnMainThread:selector
															  withObject:sess
														   waitUntilDone:NO];
        [pool drain];
    }
}

// Streaming error. Called when streaming cannot start or continue
static void streaming_error(sp_session *session, sp_error error) {
	
	SPSession *sess = (SPSession *)sp_session_userdata(session);
	SEL selector = @selector(session:didEncounterStreamingError:);
	
	if ([[sess playbackDelegate] respondsToSelector:selector]) {
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        [(id <SPSessionPlaybackDelegate>)[sess playbackDelegate] session:sess
											  didEncounterStreamingError:[NSError spotifyErrorWithCode:error]];
        [pool drain];
    }
}

// Called when offline synchronization status is updated
static void offline_status_updated(sp_session *session) {
	
	SPSession *sess = (SPSession *)sp_session_userdata(session);
	
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	[sess willChangeValueForKey:@"offlineSyncing"];
	[sess didChangeValueForKey:@"offlineSyncing"];
	
	[sess willChangeValueForKey:@"offlineTracksRemaining"];
	[sess didChangeValueForKey:@"offlineTracksRemaining"];
	
	[sess willChangeValueForKey:@"offlinePlaylistsRemaining"];
	[sess didChangeValueForKey:@"offlinePlaylistsRemaining"];
	
	[sess willChangeValueForKey:@"offlineStatistics"];
	[sess didChangeValueForKey:@"offlineStatistics"];
	
	for (SPPlaylist *playlist in [sess.playlistCache allValues]) {
		[playlist willChangeValueForKey:@"offlineStatus"];
		[playlist didChangeValueForKey:@"offlineStatus"];
		
		[playlist willChangeValueForKey:@"offlineDownloadProgress"];
		[playlist didChangeValueForKey:@"offlineDownloadProgress"];
	}
	
	[pool drain];
}

static sp_session_callbacks _callbacks = {
	&logged_in,
	&logged_out,
	&metadata_updated,
	&connection_error,
	&message_to_user,
	&notify_main_thread,
	&music_delivery,
	&play_token_lost,
	&log_message,
	&end_of_track,
	&streaming_error,
	NULL, //userinfo_updated
	NULL, //start_playback
	NULL, //stop_playback
	NULL, //get_audio_buffer_stats
	&offline_status_updated
};

#pragma mark -

static NSString * const kSPSessionKVOContext = @"kSPSessionKVOContext";

@implementation SPSession

static SPSession *sharedSession;

+(SPSession *)sharedSession {
	return sharedSession;
}

+(void)initializeSharedSessionWithApplicationKey:(NSData *)appKey
									   userAgent:(NSString *)userAgent
										   error:(NSError **)error {
	
	[sharedSession release];
	sharedSession = [[SPSession alloc] initWithApplicationKey:appKey
													userAgent:userAgent
														error:error];	
}

+(NSString *)libSpotifyBuildId {
	return [NSString stringWithUTF8String:sp_build_id()];
}

-(id)init {
	// This will always fail.
	return [self initWithApplicationKey:nil userAgent:nil error:nil];
}

-(id)initWithApplicationKey:(NSData *)appKey
				  userAgent:(NSString *)userAgent
					  error:(NSError **)error {
	
	if ((self = [super init])) {
        
        trackCache = [[NSMutableDictionary alloc] init];
        userCache = [[NSMutableDictionary alloc] init];
		playlistCache = [[NSMutableDictionary alloc] init];
		
		[self addObserver:self
               forKeyPath:@"connectionState"
                  options:0
                  context:kSPSessionKVOContext];
		
		[self addObserver:self
			   forKeyPath:@"starredPlaylist.tracks"
				  options:NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew
				  context:kSPSessionKVOContext];
		
		if (appKey == nil || [userAgent length] == 0) {
			[self release];
			return nil;
		}
		
		// Find the application support directory for settings
		
		NSString *applicationSupportDirectory = nil;
		NSArray *potentialDirectories = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory,
																			NSUserDomainMask,
																			YES);
		
		if ([potentialDirectories count] > 0) {
			applicationSupportDirectory = [[potentialDirectories objectAtIndex:0] stringByAppendingPathComponent:userAgent];
		} else {
			applicationSupportDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:userAgent];
		}
		
		if (![[NSFileManager defaultManager] fileExistsAtPath:applicationSupportDirectory]) {
			if (![[NSFileManager defaultManager] createDirectoryAtPath:applicationSupportDirectory
										   withIntermediateDirectories:YES
															attributes:nil
																 error:error]) {
				[self release];
				return nil;
			}
		}
		
		// Find the caches directory for cache
		
		NSString *cacheDirectory = nil;
		
		NSArray *potentialCacheDirectories = NSSearchPathForDirectoriesInDomains(NSCachesDirectory,
																				 NSUserDomainMask,
																				 YES);
		
		if ([potentialCacheDirectories count] > 0) {
			cacheDirectory = [[potentialCacheDirectories objectAtIndex:0] stringByAppendingPathComponent:userAgent];
		} else {
			cacheDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:userAgent];
		}
		
		if (![[NSFileManager defaultManager] fileExistsAtPath:cacheDirectory]) {
			if (![[NSFileManager defaultManager] createDirectoryAtPath:cacheDirectory
										   withIntermediateDirectories:YES
															attributes:nil
																 error:error]) {
				[self release];
				return nil;
			}
		}
		
		sp_session_config config;
		
		config.api_version = SPOTIFY_API_VERSION;
		config.application_key = [appKey bytes];
		config.application_key_size = [appKey length];
		config.user_agent = [userAgent UTF8String];
		config.settings_location = [applicationSupportDirectory UTF8String];
		config.cache_location = [cacheDirectory UTF8String];
		config.userdata = (void *)self;
		config.callbacks = &_callbacks;
		
		sp_error createError = sp_session_create(&config, &session);
		
		if (createError != SP_ERROR_OK) {
			session = NULL;
			if (error != NULL) {
				*error = [NSError spotifyErrorWithCode:createError];
			}
			[self release];
			return nil;
		}
	}
	
	return self;
}

-(void)attemptLoginWithUserName:(NSString *)userName 
					   password:(NSString *)password
			rememberCredentials:(BOOL)rememberMe {
    
	if ([userName length] == 0 || [password length] == 0)
		return;
	
	[self logout];
	sp_session_login(session, [userName UTF8String], [password UTF8String], rememberMe);
}

-(BOOL)attemptLoginWithStoredCredentials:(NSError **)error {
	
	sp_error errorCode = sp_session_relogin(session);
	
	if (errorCode != SP_ERROR_OK) {
		if (error != NULL) {
			*error = [NSError spotifyErrorWithCode:errorCode];
		}
		return NO;
	}
	return YES;
}

-(NSString *)storedCredentialsUserName {
	
	char userNameBuffer[300];
	int userNameLength = sp_session_remembered_user(session, (char *)&userNameBuffer, sizeof(userNameBuffer));
	
	if (userNameLength == -1)
		return nil;
	
	NSString *userName = [NSString stringWithUTF8String:(char *)&userNameBuffer];
	if ([userName length] > 0)
		return userName;
	else
		return nil;
}

-(void)forgetStoredCredentials {
	sp_session_forget_me(session);
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (context == kSPSessionKVOContext) {
		
		if ([keyPath isEqualToString:@"starredPlaylist.tracks"]) {
			// Bit of a hack to KVO the starred-ness of tracks.
			
			NSArray *oldStarredTracks = [change valueForKey:NSKeyValueChangeOldKey];
			if (oldStarredTracks == (id)[NSNull null])
				oldStarredTracks = nil;
			
			NSArray *newStarredTracks = [change valueForKey:NSKeyValueChangeNewKey];
			if (newStarredTracks == (id)[NSNull null])
				newStarredTracks = nil;
			
			NSMutableSet *someTracks = [NSMutableSet set];
			[someTracks addObjectsFromArray:newStarredTracks];
			[someTracks addObjectsFromArray:oldStarredTracks];
			
			[someTracks makeObjectsPerformSelector:@selector(willChangeValueForKey:) withObject:@"starred"];
			[someTracks makeObjectsPerformSelector:@selector(didChangeValueForKey:) withObject:@"starred"];
			
			return;
		
        } else if ([keyPath isEqualToString:@"connectionState"]) {
                    
            if ([self connectionState] == SP_CONNECTION_STATE_LOGGED_IN || [self connectionState] == SP_CONNECTION_STATE_OFFLINE) {
                
                if (inboxPlaylist == nil) {
                    sp_playlist *pl = sp_session_inbox_create(session);
                    [self setInboxPlaylist:[self playlistForPlaylistStruct:pl]];
                    sp_playlist_release(pl);
                }
                
                if (starredPlaylist == nil) {
                    sp_playlist *pl = sp_session_starred_create(session);
                    [self setStarredPlaylist:[self playlistForPlaylistStruct:pl]];
                    sp_playlist_release(pl);
                }
                
                if (userPlaylists == nil) {
                    sp_playlistcontainer *plc = sp_session_playlistcontainer(session);
                    [self setUserPlaylists:[[[SPPlaylistContainer alloc] initWithContainerStruct:plc inSession:self] autorelease]];
                }

                [self setUser:[SPUser userWithUserStruct:sp_session_user(session)
                                                      inSession:self]];
				
				int encodedLocale = sp_session_user_country(session);
				char localeId[3];
				localeId[0] = encodedLocale >> 8 & 0xFF;
				localeId[1] = encodedLocale & 0xFF;
				localeId[2] = 0;
				NSString *localeString = [NSString stringWithUTF8String:(const char *)&localeId];
				self.locale = [[[NSLocale alloc] initWithLocaleIdentifier:localeString] autorelease];
				
                NSUInteger friendCount = sp_session_num_friends(session);
                if (friendCount > 0) {
                    NSMutableArray *newFriends = [NSMutableArray arrayWithCapacity:friendCount];
                    NSUInteger currentFriend = 0;
                    for (currentFriend = 0; currentFriend < friendCount; currentFriend++) {
                        sp_user *friend = sp_session_friend(session, (int)friendCount);
                        if (friend != NULL) {
                            [newFriends addObject:[SPUser userWithUserStruct:friend inSession:self]];
                        }
                    }
                    [self setFriends:[NSArray arrayWithArray:newFriends]];
                }
            }
            
            if ([self connectionState] == SP_CONNECTION_STATE_LOGGED_OUT) {
				
				self.inboxPlaylist = nil;
				self.starredPlaylist = nil;
				self.userPlaylists = nil;
				self.user = nil;
				self.friends = nil;
				self.locale = nil;
            }
            return;
        }
    } 
    
    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

-(sp_connectionstate)connectionState {
    if (session != NULL) {
        return sp_session_connectionstate(session);
    } else {
        return SP_CONNECTION_STATE_UNDEFINED;
    }
}

-(void)logout {
	[trackCache removeAllObjects];
	[userCache removeAllObjects];
	[playlistCache removeAllObjects];
	self.inboxPlaylist = nil;
	self.starredPlaylist = nil;
	self.userPlaylists = nil;
	self.user = nil;
	self.friends = nil;
	self.locale = nil;
	
	if (session != NULL) {
        sp_session_logout(session);
    }
}

@synthesize playlistCache;
@synthesize inboxPlaylist;
@synthesize starredPlaylist;
@synthesize userPlaylists;
@synthesize user;
@synthesize friends;
@synthesize locale;

-(SPTrack *)trackForTrackStruct:(sp_track *)spTrack {
    
    NSValue *ptrValue = [NSValue valueWithPointer:spTrack];
    SPTrack *cachedTrack = [trackCache objectForKey:ptrValue];
    
    if (cachedTrack != nil) {
        return cachedTrack;
    }
    
    cachedTrack = [[SPTrack alloc] initWithTrackStruct:spTrack
                                                    inSession:self];
    [trackCache setObject:cachedTrack forKey:ptrValue];
    return [cachedTrack autorelease];
}

-(SPUser *)userForUserStruct:(sp_user *)spUser {
    
    NSValue *ptrValue = [NSValue valueWithPointer:spUser];
    SPUser *cachedUser = [userCache objectForKey:ptrValue];
    
    if (cachedUser != nil) {
        return cachedUser;
    }
    
    cachedUser = [[SPUser alloc] initWithUserStruct:spUser
                                                 inSession:self];
    [userCache setObject:cachedUser forKey:ptrValue];
    return [cachedUser autorelease];
}

-(SPPlaylist *)playlistForPlaylistStruct:(sp_playlist *)playlist {
	
	NSValue *ptrValue = [NSValue valueWithPointer:playlist];
	SPPlaylist *cachedPlaylist = [playlistCache objectForKey:ptrValue];
	
	if (cachedPlaylist != nil) {
		return cachedPlaylist;
	}
	
	cachedPlaylist = [[SPPlaylist alloc] initWithPlaylistStruct:playlist
															 inSession:self];
	[playlistCache setObject:cachedPlaylist forKey:ptrValue];
	return [cachedPlaylist autorelease];
}

-(SPPlaylistFolder *)playlistFolderForFolderId:(sp_uint64)playlistId inContainer:(SPPlaylistContainer *)aContainer {
	
	NSNumber *wrappedId = [NSNumber numberWithUnsignedLongLong:playlistId];
	SPPlaylistFolder *cachedPlaylistFolder = [playlistCache objectForKey:wrappedId];
	
	if (cachedPlaylistFolder != nil) {
		return cachedPlaylistFolder;
	}
	
	cachedPlaylistFolder = [[SPPlaylistFolder alloc] initWithPlaylistFolderId:playlistId
																	container:aContainer
																	inSession:self];
	
	[playlistCache setObject:cachedPlaylistFolder forKey:wrappedId];
	return [cachedPlaylistFolder autorelease];
}

-(SPTrack *)trackForURL:(NSURL *)url {
	
	if ([url spotifyLinkType] == SP_LINKTYPE_TRACK) {
		sp_link *link = [url createSpotifyLink];
		if (link != NULL) {
			sp_track *track = sp_link_as_track(link);
			sp_link_release(link);
			return [self trackForTrackStruct:track];
		}
	}
	
	return nil;
}

-(SPUser *)userForURL:(NSURL *)url {
	
	if ([url spotifyLinkType] == SP_LINKTYPE_PROFILE) {
		sp_link *link = [url createSpotifyLink];
		if (link != NULL) {
			sp_user *aUser = sp_link_as_user(link);
			sp_link_release(link);
			return [self userForUserStruct:aUser];
		}
	}
	
	return nil;
}

-(SPPlaylist *)playlistForURL:(NSURL *)url {
	
	if ([url spotifyLinkType] == SP_LINKTYPE_PLAYLIST) {
		sp_link *link = [url createSpotifyLink];
		if (link != NULL) {
			sp_playlist *aPlaylist = sp_playlist_create(session, link);
			sp_link_release(link);
			SPPlaylist *playlist = [self playlistForPlaylistStruct:aPlaylist];
			sp_playlist_release(aPlaylist);
			return playlist;
		}
	}
	
	return nil;
}

-(SPSearch *)searchForURL:(NSURL *)url {
	return [SPSearch searchWithURL:url inSession:self];
}

-(SPAlbum *)albumForURL:(NSURL *)url {
	return [SPAlbum albumWithAlbumURL:url inSession:self];
}

-(SPArtist *)artistForURL:(NSURL *)url {
	return [SPArtist artistWithArtistURL:url];
}

-(SPImage *)imageForURL:(NSURL *)url {
	return [SPImage imageWithImageURL:url inSession:self];
}

-(id)objectRepresentationForSpotifyURL:(NSURL *)aSpotifyUrlOfSomeKind linkType:(sp_linktype *)outLinkType {
	
	if (aSpotifyUrlOfSomeKind == nil)
		return nil;
	
	sp_linktype linkType = [aSpotifyUrlOfSomeKind spotifyLinkType];
	
	if (outLinkType != NULL) 
		*outLinkType = linkType;
	
	switch (linkType) {
		case SP_LINKTYPE_TRACK:
			return [self trackForURL:aSpotifyUrlOfSomeKind];
			break;
		case SP_LINKTYPE_ALBUM:
			return [self albumForURL:aSpotifyUrlOfSomeKind];
			break;
		case SP_LINKTYPE_ARTIST:
			return [SPArtist artistWithArtistURL:aSpotifyUrlOfSomeKind];
			break;
		case SP_LINKTYPE_SEARCH:
			return [self searchForURL:aSpotifyUrlOfSomeKind];
			break;
		case SP_LINKTYPE_PLAYLIST:
			return [self playlistForURL:aSpotifyUrlOfSomeKind];
			break;
		case SP_LINKTYPE_PROFILE:
			return [self userForURL:aSpotifyUrlOfSomeKind];
			break;
		case SP_LINKTYPE_STARRED:
			return [self starredPlaylist];
			break;
		case SP_LINKTYPE_IMAGE:
			return [self imageForURL:aSpotifyUrlOfSomeKind];
			break;
			
		default:
			return nil;
			break;
	}	
}

-(SPPostTracksToInboxOperation *)postTracks:(NSArray *)tracks 
									 toInboxOfUser:(NSString *)targetUserName
									   withMessage:(NSString *)aFriendlyMessage
										  delegate:(id <SPPostTracksToInboxOperationDelegate>)operationDelegate {
	
	return [[[SPPostTracksToInboxOperation alloc] initBySendingTracks:tracks
																	  toUser:targetUserName
																	 message:aFriendlyMessage
																   inSession:self
																	delegate:operationDelegate] autorelease];	
}

#pragma mark Properties

-(void)setPreferredBitrate:(sp_bitrate)bitrate {
    sp_session_preferred_bitrate(session, bitrate);
}

-(void)setMaximumCacheSizeMB:(size_t)maximumCacheSizeMB {
    sp_session_set_cache_size(session, maximumCacheSizeMB);
}

-(NSUInteger)offlineTracksRemaining {
	return sp_offline_tracks_to_sync(session);
}

-(NSUInteger)offlinePlaylistsRemaining {
	return sp_offline_num_playlists(session);
}

-(NSDictionary *)offlineStatistics {
	
	sp_offline_sync_status status;
	sp_offline_sync_get_status(session, &status);
	
	NSMutableDictionary *mutableStats = [NSMutableDictionary dictionary];
	[mutableStats setValue:[NSNumber numberWithInt:status.copied_tracks] forKey:SPOfflineStatisticsCopiedTrackCountKey];
	[mutableStats setValue:[NSNumber numberWithLongLong:status.copied_bytes] forKey:SPOfflineStatisticsCopiedTrackSizeKey];
	
	[mutableStats setValue:[NSNumber numberWithInt:status.done_tracks] forKey:SPOfflineStatisticsDoneTrackCountKey];
	[mutableStats setValue:[NSNumber numberWithLongLong:status.done_bytes] forKey:SPOfflineStatisticsDoneTrackSizeKey];
	
	[mutableStats setValue:[NSNumber numberWithInt:status.queued_tracks] forKey:SPOfflineStatisticsQueuedTrackCountKey];
	[mutableStats setValue:[NSNumber numberWithLongLong:status.queued_bytes] forKey:SPOfflineStatisticsQueuedTrackSizeKey];
	
	[mutableStats setValue:[NSNumber numberWithInt:status.error_tracks] forKey:SPOfflineStatisticsFailedTrackCountKey];
	[mutableStats setValue:[NSNumber numberWithInt:status.willnotcopy_tracks] forKey:SPOfflineStatisticsWillNotCopyTrackCountKey];
	[mutableStats setValue:[NSNumber numberWithBool:status.syncing] forKey:SPOfflineStatisticsIsSyncingKey];
	
	return [NSDictionary dictionaryWithDictionary:mutableStats];
}

-(NSTimeInterval)offlineKeyTimeRemaining {
	return (NSTimeInterval)sp_offline_time_left(session);
}

-(BOOL)isOfflineSyncing {
	sp_offline_sync_status status;
	sp_offline_sync_get_status(session, &status);
	return status.syncing;
}

@synthesize delegate;
@synthesize playbackDelegate;
@synthesize session;

#pragma mark Playback

-(BOOL)preloadTrackForPlayback:(SPTrack *)aTrack error:(NSError **)error {
	if (aTrack != nil) {
		sp_error errorCode = sp_session_player_prefetch(session, [aTrack track]);
		if (errorCode != SP_ERROR_OK && error != nil) {
			*error = [NSError spotifyErrorWithCode:errorCode];
		}
		return errorCode == SP_ERROR_OK;
	}
	
	if (error != NULL)
		*error = [NSError spotifyErrorWithCode:SP_ERROR_TRACK_NOT_PLAYABLE];
	
	return NO;
}

-(BOOL)playTrack:(SPTrack *)aTrack error:(NSError **)error {
	if (aTrack != nil) {
		sp_error errorCode = sp_session_player_load(session, [aTrack track]);
		if (errorCode == SP_ERROR_OK) {
			[self setPlaying:YES];
		} else if (error != nil) {
			*error = [NSError spotifyErrorWithCode:errorCode];
		}
		return errorCode == SP_ERROR_OK;
	}
	
	if (error != NULL)
		*error = [NSError spotifyErrorWithCode:SP_ERROR_TRACK_NOT_PLAYABLE];
		
	return NO;
}

-(void)seekPlaybackToOffset:(NSTimeInterval)offset {
	sp_session_player_seek(session, (int)offset * 1000);
}

-(void)setPlaying:(BOOL)nowPlaying {
	sp_session_player_play(session, nowPlaying);
	playing = nowPlaying;
}

-(BOOL)isPlaying {
	return playing;
}

-(void)unloadPlayback {
	self.playing = NO;
	sp_session_player_unload(session);
}


#pragma mark libSpotify Run Loop

-(void)prodSession {
    
    // Cancel previous delayed calls to this 
    [NSObject cancelPreviousPerformRequestsWithTarget:self
                                             selector:_cmd
                                               object:nil];
    
    int timeout = 0;
    sp_session_process_events(session, &timeout);
    
    [self performSelector:_cmd
               withObject:nil
               afterDelay:((double)timeout / 1000.0)];
    
}

#pragma mark -

-(void)dealloc {
    
	[self unloadPlayback];
    [self removeObserver:self forKeyPath:@"connectionState"];
	[self removeObserver:self forKeyPath:@"starredPlaylist.tracks"];
    
	if (session != NULL)
		[self logout];
	
    self.inboxPlaylist = nil;
	self.starredPlaylist = nil;
	self.userPlaylists = nil;
	self.user = nil;
	self.friends = nil;
	self.locale = nil;
    
    [trackCache release];
    [userCache release];
	[playlistCache release];
    
    [super dealloc];
}

@end

