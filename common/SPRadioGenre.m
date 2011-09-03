//
//  SPRadioGenre.m
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


#import "SPRadioGenre.h"


#pragma mark - Radio genres name

typedef struct {
    NSString * const name;
    sp_radio_genre genre;
} spc_radio_genre_name;

spc_radio_genre_name radioGenresName[] = {
    { @"AltPopRock",     SP_RADIO_GENRE_ALT_POP_ROCK },
    { @"Blues",          SP_RADIO_GENRE_BLUES        },
    { @"Country",        SP_RADIO_GENRE_COUNTRY      },
    { @"Disco",          SP_RADIO_GENRE_DISCO        },
    { @"Funk",           SP_RADIO_GENRE_FUNK         },
    { @"Hardrock",       SP_RADIO_GENRE_HARD_ROCK    },
    { @"HeavyMetal",     SP_RADIO_GENRE_HEAVY_METAL  },
    { @"Rap",            SP_RADIO_GENRE_RAP          },
    { @"House",          SP_RADIO_GENRE_HOUSE        },
    { @"Jazz",           SP_RADIO_GENRE_JAZZ         },
    { @"NewWave",        SP_RADIO_GENRE_NEW_WAVE     },
    { @"RnB",            SP_RADIO_GENRE_RNB          },
    { @"Pop",            SP_RADIO_GENRE_POP          },
    { @"Punk",           SP_RADIO_GENRE_PUNK         },
    { @"Reggae",         SP_RADIO_GENRE_REGGAE       },
    { @"PopRock",        SP_RADIO_GENRE_POP_ROCK     },
    { @"Soul",           SP_RADIO_GENRE_SOUL         },
    { @"Techno",         SP_RADIO_GENRE_TECHNO       },
};
const size_t radioGenresNameSize = sizeof(radioGenresName) / sizeof(spc_radio_genre_name);


#pragma mark -

@interface SPRadioGenre()

- (id)initWithGenre:(sp_radio_genre)genre name:(NSString *)name;

@end


static NSArray *radioGenres = nil;


@implementation SPRadioGenre

#pragma mark - Properties

@synthesize genre = _genre;
@synthesize name = _name;


#pragma mark - Init/Dealloc

- (id)init
{
    [self release];
    return nil;
}

- (id)initWithGenre:(sp_radio_genre)genre name:(NSString *)name
{
    if (self = [super init]) {
        _genre = genre;
        _name = name;
    }
    
    return self;
}

- (void)dealloc
{
    [_name release];
    
    [super dealloc];
}


#pragma mark - Class

+ (NSArray *)radioGenres
{
    if (radioGenres == nil) {
        NSMutableArray *newRadioGenres = [NSMutableArray arrayWithCapacity:radioGenresNameSize];
        
        for (NSInteger i=0; i<radioGenresNameSize; i++) {
            spc_radio_genre_name radioGenreName = radioGenresName[i];
            SPRadioGenre *radioGenre = [[[self class] alloc] initWithGenre:radioGenreName.genre name:radioGenreName.name];
            [newRadioGenres addObject:radioGenre];
        }
        
        radioGenres = newRadioGenres;
    }
    
    return radioGenres;
}

+ (SPRadioGenre *)radioGenre:(sp_radio_genre)genre
{
    for (SPRadioGenre *radioGenre in [self radioGenres]) {
        if (radioGenre.genre == genre) {
            return radioGenre;
        }
    }
    
    return nil;
}

@end
