import std/json
from std/sugar import collect
from std/sets import items, contains


import chronos
import chronos/threadsync
import results



import ../core




type
  Backend* = object
    signal*: ThreadSignalPtr
    toBData*, fromBData*: cstring

  TaskSnippetJson* = object
    address*: uint
    path*, snippet*, name*, key*, staffPrefix*: string

  TaskJson* = object
    address*, snippet*: uint
    depends*: seq[uint]
    categories*: seq[string]
    inPool*: bool

  InstrumentJson* = object
    address*: uint
    name*, staffPrefix*: string

  PerformerJson* = object
    address*: uint
    name*: string
    categories*: seq[string]
    instrument*: uint
    minVolume*, maxVolume*: float
    key*, clef*: string

proc fireSync*(b: var Backend, timeout = InfiniteDuration): bool =
  fireSync(b.signal, timeout).expect("improper signal while firing")

proc sendToB*(b: var Backend;
              m: string;
              node: JsonNode = nil;
              timeout = InfiniteDuration;
             ): bool =
  let n = if node.isNil: newJObject() else: node
  if n.kind == JObject:
    n["method"] = % m
  let s = $n
  if not b.toBData.isNil:
    freeShared(cast[ptr char](b.toBData))
  b.toBData = cast[cstring](createSharedU(char, s.len + 1))
  copyMem(b.toBData, s.cstring, s.len + 1)
  fireSync(b, timeout)

template intAddr*(x: typed): uint =
  cast[uint](cast[pointer](x))



func toJson*(x: TaskSnippet): TaskSnippetJson = 
  TaskSnippetJson(address: intAddr(x),
                  path: x.path.string,
                  snippet: x.snippet,
                  name: x.name,
                  key: x.key,
                  staffPrefix: x.staffPrefix,
                 )
func toJson*(x: Task; pool: TaskPool): TaskJson =
  let
    depends = collect:
      for i in x.depends:
        intAddr(x.snippet)
    categories = collect:
      for i in x.allowedCategories:
        i.string
  TaskJson(address: intAddr(x),
           snippet: intAddr(x.snippet),
           depends: depends,
           categories: categories,
           inPool: x in pool.initialPool,
          )

func toJson*(x: Instrument): InstrumentJson =
  InstrumentJson(address: intAddr(x),
                 name: x.name,
                 staffPrefix: x.staffPrefix,
                )

func toJson*(x: Performer): PerformerJson =
  let
    categories = collect:
      for i in x.categories:
        i.string
  PerformerJson(address: intAddr(x),
                name: x.name,
                categories: categories,
                instrument: intAddr(x.instrument),
                minVolume: x.minVolume,
                maxVolume: x.maxVolume,
                key: x.key,
                clef: x.clef,
               )

proc waitSync*(b: var Backend, timeout = InfiniteDuration): bool =
  waitSync(b.signal, timeout).expect("improper signal while waiting")

proc popJson*(b: var Backend; s: var cstring): JsonNode =
  discard waitSync(b)

  if s.isNil:
    return newJNull()

  defer:
    freeShared(cast[ptr char](s))
    s = nil
  let json = parseJson($s)
  if json.kind == JObject:
    if "error" in json:
      raise ValueError.newException(json["error"].str)
    json.delete("error")
  json
