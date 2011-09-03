//
//  SPRadioSearch.m
//  CocoaLibSpotify
//
//  Created by Adrien Brault on 03/09/11.

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


#import "SPRadioSearch.h"
#import "SPSession.h"
#import "SPURLExtensions.h"
#import "SPErrorExtensions.h"
#import "SPTrack.h"
#import "SPRadioGenre.h"


@interface SPRadioSearch ()

- (id)initWithSession:(SPSession *)aSession; // Designated initialiser.
- (void)searchDidComplete:(sp_search *)search;

@property (nonatomic, retain) NSArray *tracks;

@property (nonatomic, assign) NSInteger requestedTrackResults;
@property (nonatomic, assign) BOOL hasExhaustedTrackResults;

@property (nonatomic, copy) NSError *searchError;

@property (nonatomic, copy) NSURL *spotifyURL;
@property (nonatomic, retain) SPSession *session;
@property (nonatomic) sp_search *activeSearch;

@end


#pragma mark - C Callbacks

void radio_search_complete(sp_search *result, void *userdata);
void radio_search_complete(sp_search *result, void *userdata) {
	SPRadioSearch *search = userdata;
	[search searchDidComplete:result];
}


#pragma mark -

@implementation SPRadioSearch

#pragma mark - Properties

@synthesize genre = _genre;
@synthesize fromYear = _fromYear;
@synthesize toYear = _toYear;
@synthesize pageSize = _pageSize;

@synthesize hasExhaustedTrackResults = _hasExhaustedTrackResults;
@synthesize tracks = _tracks;
@synthesize requestedTrackResults = _requestedTrackResults;
@synthesize searchError = _searchError;
@synthesize searchInProgress = _searchInProgress;
@synthesize session = _session;
@synthesize spotifyURL = _spotifyURL;
@synthesize activeSearch = _activeSearch;

- (BOOL)searchInProgress
{
	return self.activeSearch != NULL && !sp_search_is_loaded(self.activeSearch);
}

- (void)setActiveSearch:(sp_search *)search
{
	if (search != _activeSearch) {
		if (_activeSearch != NULL) {
			sp_search_release(_activeSearch);
		}
        
		if (search != NULL) {
			sp_search_add_ref(search);
		}
        
		_activeSearch = search;
	}
}


#pragma mark - Init/Dealloc

- (id)initWithSession:(SPSession *)session
{
	if (session == nil) {
        [self release];
        return nil;
    }
    
    if ((self = [super init])) {
		self.session = session;
		self.tracks = [NSArray array];
	}
    
	return self;
}

- (id)initWithRadioGenre:(sp_radio_genre)genre
                fromYear:(NSUInteger)fromYear
                  toYear:(NSUInteger)toYear
               inSession:(SPSession *)session
{
    return [self initWithRadioGenre:genre
                           fromYear:fromYear
                             toYear:toYear
                           pageSize:kSPRadioSearchDefaultSearchPageSize
                          inSession:session];
}

- (id)initWithRadioGenre:(sp_radio_genre)genre
                fromYear:(NSUInteger)fromYear
                  toYear:(NSUInteger)toYear
                pageSize:(NSInteger)pageSize
               inSession:(SPSession *)session
{
    if ((self = [self initWithSession:session])) {
        _genre = genre;
        _fromYear = fromYear;
        _toYear = toYear;
        _pageSize = pageSize;
        
        [self addPage];
    }
    
    return self;
}

- (id)initWithRadioGenres:(id <NSFastEnumeration>)genres
                 fromYear:(NSUInteger)fromYear
                   toYear:(NSUInteger)toYear
                inSession:(SPSession *)session
{
    return [self initWithRadioGenres:genres
                            fromYear:fromYear
                              toYear:toYear
                            pageSize:kSPRadioSearchDefaultSearchPageSize
                           inSession:session];
}

- (id)initWithRadioGenres:(id <NSFastEnumeration>)genres
                 fromYear:(NSUInteger)fromYear
                   toYear:(NSUInteger)toYear
                 pageSize:(NSInteger)pageSize
                inSession:(SPSession *)session
{
    sp_radio_genre genre = 0;
    for (SPRadioGenre *radioGenre in genres) {
        genre |= radioGenre.genre;
    }
    
    return [self initWithRadioGenre:genre
                           fromYear:fromYear
                             toYear:toYear
                           pageSize:pageSize
                          inSession:session];
}

- (void)dealloc
{
    [_searchError release];
    [_tracks release];
    [_session release];
    [_spotifyURL release];
    
    _activeSearch = NULL;
    
    [super dealloc];
}


#pragma mark - Perform search

- (BOOL)addPage
{
	if (!self.searchInProgress) {
		int trackOffset = 0, trackCount = 0;
		
		if (!self.hasExhaustedTrackResults) {
			trackOffset = (int)self.tracks.count;
			trackCount = (int)self.pageSize;
		}
		
		if (trackCount > 0) {
            sp_search *newSearch = sp_radio_search_create(self.session.session,
                                                          self.fromYear,
                                                          self.toYear,
                                                          self.genre,
                                                          &radio_search_complete,
                                                          self);
            
			if (newSearch != NULL) {
				self.activeSearch = newSearch;
				sp_search_release(newSearch);
                
				if (self.spotifyURL == nil) {
					sp_link *searchLink = sp_link_create_from_search(self.activeSearch);
                    
					if (searchLink != NULL) {
						self.spotifyURL = [NSURL urlWithSpotifyLink:searchLink];
						sp_link_release(searchLink);
					}
				}
                
				return YES;
			} 
		} 
	}
    
	return NO;
}


#pragma mark - Handle results

- (void)searchDidComplete:(sp_search *)search
{
	[self willChangeValueForKey:@"searchInProgress"];
	
	sp_error error = sp_search_error(search);
	if (error != SP_ERROR_OK) {
		self.searchError = [NSError spotifyErrorWithCode:error];
	}
	
	int trackCount = sp_search_num_tracks(search);
	if (trackCount > 0) {
		NSMutableArray *newTracks = [NSMutableArray array];
		
		for (int currentTrack = 0; currentTrack < trackCount; currentTrack++) {
			SPTrack *track = [SPTrack trackForTrackStruct:sp_search_track(search, currentTrack)
                                                inSession:self.session];			
			if (track != nil) {
				[newTracks addObject:track];
			}
		}
		trackCount = (int)[newTracks count];
		self.tracks = [self.tracks arrayByAddingObjectsFromArray:newTracks];
	}
	
	self.hasExhaustedTrackResults = (trackCount < self.pageSize);
	self.requestedTrackResults += trackCount;
	
	[self didChangeValueForKey:@"searchInProgress"];
}


@end

