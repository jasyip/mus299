import std/[paths, tempfiles]
import std/strutils
import std/sequtils
import std/sets
import core


proc newTask*(lilypondSrc: string; categories: string): Task =
  var splitted = categories.split(",")
  splitted.applyIt(it.strip())
  new(result)
  result.allowedCategories.incl("")
  for category in splitted:
    result.allowedCategories.incl(category)

  if splitted.len != result.allowedCategories.len - 1:
    raise newException(ValueError, "There were some invalid categories")

  result.folderPath = Path(createTempDir("mus299", ""))
  writeFile(cast[string](result.folderPath / Path("source.ly")), lilypondSrc)
