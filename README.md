# gx-perl6

A command-line extension for GX and a CompUnit::Repository for Perl 6.

## Usage

Follow the GX command-line usage and the hooks will be handled internally.

```perl6
use CompUnit::Repository::GX # Be sure to add this line first as you would lib
use Foo::Bar # Your modules will be searched within gx's directory
```

## Dependency Specification

```
Module::Name:auth<gx:username>:ver(v1.0.2)
```

The content storage name is `gx` and the username is whatever gx sets
as `author` in `package.json` (which for me, is my linux username).
