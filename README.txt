CocoaLibSpotify
===============

CocoaLibSpotify is and Objective-C wrapper around our libspotify library. It provides easy access to libspotify's features in a friendly, KVC/O compliant Objective-C wrapper.

Building
========

The Xcode project was built in Xcode 4.0. It should work in Xcode 3.2.x, but it hasn't been tested as of yet.

CocoaLibSpotify requires libspotify.framework, which isn't included in the repository. The Xcode project includes a build step to download and unpack it from developer.spotify.com automatically. If this fails for some reason, download it manually from developer.spotify.com and unpack it into the project folder.

The built CocoaLibSpotify.framework contains libspotify.framework as a child framework. Sometimes, Xcode gives build errors complaining it can't find <libspotify/api.h>. If you get this, manually add the directory CocoaLibSpotify.framework is in to your project's "Framework Search Paths" build setting.

Documentation
=============

The headers of CocoaLibSpotify are well documented, and we've provided an Xcode DocSet to provide documentation right in Xcode. With these and the sample projects, you should have everything you need to dive right in!

Contact
=======

If you have any problems or find any bugs, see our GitHub page for known issues and discussion. Otherwise, we may be available in irc://irc.freenode.net/spotify. 