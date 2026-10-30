# The Loco apps this box runs (loco.nix, docs/LOCO.md). Secrets live on the box, never here.
{ pkgs, ... }:
{
  # The notes demo: CRUD on SQLite at www.piabrota.art/notes, behind one password.
  piabrota.loco.apps.notes = {
    package = pkgs.callPackage ./apps/notes { };
    path = "/notes";
    port = 5150;
    # NOTES_PASSWORD and NOTES_SECRET, written by hand on the box. The leading "-" lets the
    # service start without the file: with no password the wall stays shut, so a deploy before
    # the file exists breaks nothing.
    environmentFile = "-/var/lib/loco-secrets/notes.env";
    memoryMax = "128M";
  };
}
