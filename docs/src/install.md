# Installation

## Requirements

- Linux or OSX
- Julia >= v"1.4"
- git (Tested with "version 2.17.1")
- Node.js (Tested with "v12.4.0") - For the optional frontend

## Install & run a sample

You need to checkout two repos: The [CircoCore](https://github.com/tisztamo/CircoCore) "backend" and the [CircoCore.js](https://github.com/tisztamo/CircoCore.js) "frontend".

**In terminal #1 (backend)**

```bash
git clone git@github.com:tisztamo/CircoCore.git
cd CircoCore/
NODE_COUNT=6 bin/localcluster.sh
```

This starts a local cluster with six nodes running the sample project.

**In terminal #2 (monitoring frontend, optional)**

```bash
git clone git@github.com:tisztamo/CircoCore.js.git
cd CircoCore.js
npm install
npx ws
```

This starts a web server on port 8000. Open [http://localhost:8000](http://localhost:8000)
