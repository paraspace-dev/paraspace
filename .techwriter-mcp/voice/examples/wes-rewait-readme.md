<!-- Copied verbatim from ~/projects/writing-samples/Wes Roberts/rewait-readme.md (hand-written, per that repo's README). -->

<!-- README of rewait, a pre-AI project by this repo's author; hand-written voice reference -->
Rewait
======

![Version 2.0.0](https://img.shields.io/badge/v-2.0.0-blue)
![License MIT](https://img.shields.io/badge/license-MIT-brightgreen)
![Test Coverage 100%](https://img.shields.io/badge/test%20coverage-100%25-brightgreen)

A NodeJS library to wait for external resources to become available:

- files
- sockets
- http/https
- custom functions

For example, you may wish to wait for a database or message queue to become
available before starting your HTTP server. Rewait does that.


Install
-------

Easily install with the following NPM command, or [download a
release](https://github.com/jchook/rewait/releases).

```sh
npm i rewait
```


Why use rewait?
---------------

- Simple
- Easy to use, familiar
- No dependencies
- Tiny (~400 logical lines of code)
- 100% test coverage
- Permissive FOSS license
- Written in TypeScript
- Used in major production evironments
- Extensible


Usage
=====

For detailed usage info, [see the API documentation here](./docs).


Example
--------

See [more examples here](examples).

```javascript
const { retry, http, socket } = require('rewait')

retry(
  [
    http('http://localhost:3000'),
    http('https://localhost:3001/path/to/thing.txt'),
    socket('/var/run/app.sock'),
  ],
  {
    interval: 250, // check (at most) every 1/4 second
    timeout: 60000, // timeout after 60 seconds (on the dot)
  }
).then(() => {
  console.log('Ready!')
})
```


Custom checks
-------------

If you need custom functionality, you can easily write your own custom checks.

Simply throw an Error when "not ready".

Example:

```javascript
function customCheck(options = {}) {
  return new Promise(function() {
    if (options.neverReady) {
      throw new Error('Never ready!')
    }
    if (options.waitUntil) {
      if (+new Date() < options.waitUntil) {
        throw new Error('Not ready!')
      }
    }
    // Ready, simply by not throwing
  })
}

retry(customCheck)
```

