Media-Scripts
===
A bunch of scripts used to process media files. Here's what they do:
1. If the input is a single file, encode the video stream into x265-10bit, every audio stream into NeroAac, and copy every subtitle stream with chapter info
2. If the input is a bunch of files, create a chapter file first, then treat them as a single file, concatenating them and encode
