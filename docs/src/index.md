# Introducing CircoCore.jl

CircoCore.jl is the small inner core of the [Circo](https://github.com/Circo-dev/Circo) actor system.

You may want to use the full-featured system directly.

CircoCore.jl provides a single-threaded actor scheduler with a powerful plugin architecture, plus a few plugins to serve
minimalistic use cases.

Circo extends this system with plugins that provide multithreading, clustering, debugging, interoperability and more.

The main goal of separating these packages is to allow alternative implementations of the high level functionality. (like kernel and distros)