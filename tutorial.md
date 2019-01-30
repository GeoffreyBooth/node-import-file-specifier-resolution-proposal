# Node Modules “Hello World” Tutorial

This tutorial is meant to show what the user experience would be like for a user running Node’s classic [“Hello World” server example](https://nodejs.org/en/about/) in a version of Node that implements the [File Specifier Resolution proposal](https://github.com/GeoffreyBooth/node-import-file-specifier-resolution-proposal/). The example has been adapted to use `import` syntax instead of `require`.

## Tutorial

Let’s get started with [Node.js](https://nodejs.org/en/)! In this tutorial, we’re going to create a web server that listens at `http://localhost:3000` and responds to every request with the message `Hello World`. The tutorial assumes you already have the [latest Node.js](https://nodejs.org/en/download/) installed, which includes the [latest version of NPM](https://www.npmjs.com/get-npm).

First, create a new folder `hello-world-server` and navigate into it in a command prompt window.

Run this command:

```bash
npm init
```

NPM will ask you a series of questions. You can simply press <kbd>enter</kbd> to accept the defaults, or answer each question per your preference:

```bash
This utility will walk you through creating a package.json file.
It only covers the most common items, and tries to guess sensible defaults.

See `npm help json` for definitive documentation on these fields
and exactly what they do.

Use `npm install <pkg>` afterwards to install a package and
save it as a dependency in the package.json file.

Press ^C at any time to quit.
package name: (hello-world-server)
version: (1.0.0)
description: A web server that says hello!
use import/export syntax: (yes)
entry point: (index.js)
test command:
git repository:
keywords:
author:
license: (ISC)
About to write to /tmp/hello-world-server/package.json:

{
  "name": "hello-world-server",
  "version": "1.0.0",
  "description": "A web server that says hello!",
  "type": "esm",
  "main": "index.js",
  "scripts": {
    "test": "echo \"Error: no test specified\" && exit 1"
  },
  "author": "",
  "license": "ISC"
}


Is this OK? (yes)
```

You should now have a `package.json` in your `hello-world-server` folder, with the contents as above. This describes the files in this folder (the “package”) both for Node and for other packages to know how to interpret them.

Now create an `index.js` file in the folder, with the following contents:

```js
import http from 'http';

const hostname = '127.0.0.1';
const port = 3000;

const server = http.createServer((req, res) => {
  res.statusCode = 200;
  res.setHeader('Content-Type', 'text/plain');
  res.end('Hello World\n');
});

server.listen(port, hostname, () => {
  console.log(`Server running at http://${hostname}:${port}/`);
});
```

This code creates a web server listening on localhost port 3000, responding to every request with the text `Hello World`. Let’s see it in action!

```bash
node index.js
```

And in a web browser, go to http://localhost:3000. You should see the text `Hello World`!

## Try It Today

You can try this tutorial yourself by using a fork of Node that implements the modules proposals:

```bash
git clone git clone git@github.com:guybedford/node node-guybedford
cd node-guybedford
git checkout irp-implementation
# Build per https://github.com/nodejs/node/blob/master/doc/guides/building-node-with-ninja.md
# Install Ninja if needed (Mac): brew install ninja
./configure --ninja
ninja -C out/Release
ln -fs out/Release/node node
```

Note that this branch doesn’t have an updated NPM, so you need to replace the contents of your generated `package.json` with the contents shown in the tutorial above. Once you’ve done that, assuming you’ve completed the tutorial and saved to `~/Sites/hello-world-server`:

```bash
./node ~/Sites/hello-world-server/index.js
```
