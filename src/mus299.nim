import mus299pkg/[core, task]
import std/appdirs
import std/re
import std/paths




const
  staffJoinStr = "\p"
  varName = "task"
  expressionRe = r"\s*(?:\\\w+\s*)*\{" 

  dataDir = getDataDir() / "mus299".Path


let
  isExpression = re(r"^" & expressionRe, {reIgnoreCase, reMultiLine, reStudy})
  isAssignment = re(r"^([a-z]+)\s*=" & expressionRe, {reMultiLine, reStudy})
  sourceTemplate = readFile(string(dataDir / "template.ly".Path))
  staffTemplate = readFile(string(dataDir / "staff.ly".Path))
