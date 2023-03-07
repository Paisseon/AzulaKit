# AzulaKit
A Swift library to manipulate load commands in 64-bit Mach-O binaries.

## Prerequisites
- macOS 11 or iOS 14 device
- Xcode with Swift 5.5 or newer

## Features
- Inject multiple load commands at once
- Remove multiple load commands at once
- Nullify the code signature
- Supports both thin and fat binaries
- Parses load commands only once (per arch) for performance
- Easy to integrate into your project
- Example code in my Azula and AzulaApp repositories

## Usage
Just add AzulaKit to your project with SPM and initialise an instance of the struct AzulaKit. You can now use `inject()`, `remove()`, and `slice()` functions. These take no arguments, and handle the values given during initialisation.

`inject()` adds a load command for each String in `dylibs`, returning true if all injections succeed and false if any fail.

`remove()` removes load commands for each String in `remove`, returning true if all removals succeed and false if any fail.

`slice()` nullifies the code signature, returning true if… well you get the idea.

## Contributing
Fixing bugs, improving performance, etc. is always appreciated!

## Credits
- [Jonathan Levin][1] 
- [ParadiseDuo][2] 

[1]:	https://annas-archive.org/md5/c2f0370903c27a149b66326d9e584719
[2]:	https://github.com/paradiseduo/inject