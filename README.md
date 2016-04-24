# gx-perl6

A command-line extension for GX and a CompUnit::Repository for Perl 6.

## Usage

Follow the GX command-line usage and the hooks will be handled internally.

### Example

```shell
$ gx init --lang=perl6 # Instantiates your project in gx-verse
$ gx import QmMULTIHASH # Import multihashes and gx-perl6 will capture the meta-data needed
```

```perl6
use CompUnit::Repository::GX # Be sure to add this line first as you would lib
use Foo::Bar:auth<gx:jdoe>:ver<1.2> # Use a short or full spec name
```

## Dependency Specification

```
Module::Name:auth<gx:username>:ver(v1.0.2)
```

The content storage name is `gx` and the username is whatever gx sets
as `author` in `package.json` (which for me, is my linux username).
