# AzulaKit
A Swift library to manipulate load commands in 64-bit Mach-O binaries.

## Prerequisites
- macOS 11 or iOS 14 device
- Decrypted .ipa or Mach-O binary
- Mac with Xcode installed (developers)
- Basic ability to code in Swift (developers)

## Features
- Inject multiple load commands at once
- Remove multiple load commands at once
- Nullify the code signature
- Supports both thin and fat binaries
- Parses load commands only once for performance

## Usage
Just add AzulaKit to your project with SPM and create a struct conforming to protocol `PrettyPrinter`. The `print(_ text: String, type: PrintType)` function is what provides output to users.

Then initialise an instance of struct AzulaKit. You can now use `inject()`, `remove()`, and `slice()` functions. These take no arguments, and handle the values given when you initialised AzulaKit.

`inject()` adds a load command for each String in `dylibs`, returning true if all injections succeed and false if any fail.

`remove()` removes load commands for each String in `remove`, returning true if all removals succeed and false if any fail.

`slice()` nullifies the code signature, returning true if… well you get the idea.

## Contributing
Fixing bugs, improving performance, etc. is always appreciated! 

Currently the main issue is that on `Data.extract()` and `AzulaKit.init()`, I use `exit(1)` in case of certain errors and this is not ideal. Please let me know if you have a better solution ^^

## Credits
- [Jonathan Levin][1] 
- [ParadiseDuo][2] 

[1]:	https://annas-archive.org/md5/c2f0370903c27a149b66326d9e584719
[2]:	https://github.com/paradiseduo/inject