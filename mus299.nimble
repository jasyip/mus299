# Package

version       = "0.1.0"
author        = "Jason Yip"
description   = "MUS299 Spring 2024 Capstone Project"
license       = "GPL-3.0-only"
srcDir        = "src"
binDir        = "bin"
bin           = @["gui", "oneshot"]

from std/sugar import collect
import std/os
import std/sets

let
  libraryDir = srcDir / "mus299pkg"
  excludedDirs = collect:
    for i in ["gui"]:
      {normalizedPath(libraryDir / i)}

var stack = @[libraryDir]
installFiles = collect:
  while stack.len > 0:
    let curDir = stack.pop.normalizedPath()
    if curDir in excludedDirs:
      continue
    stack.add(listDirs(curDir))
    for i in listFiles(curDir):
      if splitFile(i).ext == ".nim":
        relativePath(i, srcDir)

# Dependencies

requires "nim ^= 2.0.0"
requires "chronos ^= 4.0.0"
requires "owlkettle ^= 3.0.0"
