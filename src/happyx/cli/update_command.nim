import
  ./utils


proc updateCommand*(args: seq[string]): int =
  var version = "head"
  if args.len > 1:
    styledEcho fgRed, "Only one argument possible for `update` command!"
  else:
    version = args[0]
  
  var v = version.toLower().strip(chars = {'v', '#'})
  case v
  of "head", "latest", "main", "master":
    updateHappyx("#head")
  else:
    if re2"\A(\d+\.\d+\.\d+)\z" in v:
      updateHappyx(v)
    else:
      shutdownCli()
      return QuitFailure
  shutdownCli()
  QuitSuccess