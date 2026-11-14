package piabrota.lib

object Files:
  /** Writes `data` to a temporary file in `path`'s folder and renames it over `path`, so a reader
    * sees the old file or the new one, never half of one. An IOException leaves no temporary file.
    */
  def replace(path: os.Path, data: Array[Byte], perms: Option[os.PermSet] = None): Unit =
    val temp = os.temp(dir = path / os.up, prefix = s".${path.last}.", deleteOnExit = false)
    try
      os.write.over(temp, data)
      perms.foreach(os.perms.set(temp, _))
      os.move(temp, path, replaceExisting = true, atomicMove = true)
    catch
      case e: java.io.IOException =>
        os.remove(temp)
        throw e
