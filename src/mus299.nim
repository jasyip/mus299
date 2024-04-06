import mus299pkg/[core, task, pool, performer]
import std/appdirs
import std/re
import std/paths



const
  staffJoinStr = "\p"
  varName = "task"
  expressionRe = r"\s*(?:\\\w+\s*)*\{" 

  dataDir = getDataDir() / "mus299".Path

  fluidsynth = "fluidsynth"
  # audio drivers alsa, pulseaudio and sdl2 allow concurrent
  fluidsynthParams = @["-i", "-l", "/usr/share/soundfonts/freepats-general-midi.sf2"]


let
  isExpression = re(r"^" & expressionRe, {reIgnoreCase, reMultiLine, reStudy})
  isAssignment = re(r"^([a-z]+)\s*=" & expressionRe, {reMultiLine, reStudy})
  sourceTemplate = readFile(string(dataDir / "template.ly".Path))
  staffTemplate = readFile(string(dataDir / "staff.ly".Path))
