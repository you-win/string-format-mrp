This is an MRP for [this Godot bug](https://github.com/godotengine/godot/issues/73258) involving a crash when formatting a string.

Tested with Godot 4 built from commit 62d4d8bfc63506fe382ae21cfe040fe4f03df8c8.

## How to test
Start the default scene. The scene should crash within 5 seconds, depending on request latency (several HTTP requests are sent beforehand which also use string formatting).

