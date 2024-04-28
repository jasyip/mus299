from std/sugar import collect
from std/sets import items, contains


import chronos
import chronos/threadsync



import ../core




type
  Backend* = object
    toB*, fromB*: ThreadSignalPtr
    toBData*, fromBData*: cstring # json string of whatever

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

proc sendToB*(b: var Backend; s: string; timeout = InfiniteDuration): Result[bool, string] =
  if not b.toBData.isNil:
    freeShared(cast[ptr char](b.toBData))
  b.toBData = cast[cstring](createSharedU(char, s.len + 1))
  copyMem(b.toBData, s.cstring, s.len + 1)
  fireSync(b.toB, timeout)

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
