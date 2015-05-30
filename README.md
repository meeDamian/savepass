# savepass [![Build Status](https://travis-ci.org/chester1000/savepass.svg)](https://travis-ci.org/chester1000/savepass) [ ![Codeship Status for chester1000/savepass](https://codeship.com/projects/71e48d30-e90c-0132-7604-26b28b7b5489/status?branch=master)](https://codeship.com/projects/82900)

This is a CLI tool managing preparing, encrypting and saving (to cloud) password/sensitive text files.

## Download

```
$ npm i -g @meedamian/savepass
```

## Usage

You can either pass CLI flags or answer questions.

```
$ savepass --help

  CLI tool archiving your keybase.io-encrypted data to Google Drive

  Usage: savepass <command>

  where <command> is one of:
      add, new, list, ls,
      remove*, rm*, get*

  Example Usage:
      savepass add [OPTIONAL <flags>]
      savepass ls

  Available add|new subcomand flags:
      --template=<templateName>
          Specify template name to be used. Available templates can be
          found in `templates/` folder.
      --keybase-user=<keybaseUsername>
          Encrypt output file for a different user then the one logged in.
      --name, --website, --login, --password, --email, --seed
          Using those flags you can pass values, to be filled into a
          template, directly from CLI. All flags accept strings or "null" to disable.
          Flag --password can only be set to null

  Specify configs in the json-formatted file:
      /Users/mee/.config/savepass/config.json

```

## Bugs and feedback

If you discover a bug please report it to:

https://github.com/chester1000/savepass/issues/new

Mail me at mee.damian@gmail.com, on twitter I'm [@meeDamian](http://twitter.com/meedamian).


## Licence

MIT @ [Damian Mee](http://meedamian.com)