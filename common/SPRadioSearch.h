//
//  SPRadioSearch.h
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


#import <Foundation/Foundation.h>
#import "CocoaLibSpotifyPlatformImports.h"


@class SPSession;


static NSInteger const kSPRadioSearchDefaultSearchPageSize = 75;
static NSInteger const kSPRadioSearchDoNotSearchPageSize = 0;


@interface SPRadioSearch : NSObject

- (id)initWithRadioGenre:(sp_radio_genre)genre
                fromYear:(NSUInteger)fromYear
                  toYear:(NSUInteger)toYear
               inSession:(SPSession *)session;

- (id)initWithRadioGenre:(sp_radio_genre)genre
                fromYear:(NSUInteger)fromYear
                  toYear:(NSUInteger)toYear
                pageSize:(NSInteger)pageSize
               inSession:(SPSession *)session;

- (BOOL)addPage;


@property (nonatomic, readonly, assign) sp_radio_genre genre;
@property (nonatomic, readonly, assign) NSUInteger fromYear;
@property (nonatomic, readonly, assign) NSUInteger toYear;

@property (nonatomic, readonly, assign) NSInteger pageSize;


@property (nonatomic, readonly) BOOL hasExhaustedTrackResults;
@property (nonatomic, readonly, retain) NSArray *tracks;

@property (nonatomic, readonly, copy) NSError *searchError;
@property (nonatomic, readonly) BOOL searchInProgress;
@property (nonatomic, readonly, retain) SPSession *session;
@property (nonatomic, readonly, copy) NSURL *spotifyURL;

@end