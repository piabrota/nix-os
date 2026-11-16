package piabrota.hermes

import piabrota.lib.{Sh, TestKit}

class ExportSkillsTest extends munit.FunSuite:
  // The job looks for git and gh before anything else; these runs end before they call either.
  private val tools = TestKit.fakes("git" -> "#!/bin/sh\nexit 1\n", "gh" -> "#!/bin/sh\nexit 1\n")
  private val noGh = TestKit.fakes("gh" -> "#!/bin/sh\nexit 1\n")

  test("normalize keeps the Agent Skills keys, sets the name and adds disable-model-invocation"):
    val text = "---\nname: other\nauthor: me\ndescription: >\n  Does a thing.\nlicense: MIT\nmetadata:\n  x: 1\n---\n# Body\n---\nkept\n"
    assertEquals(ExportSkills.normalize(text, "mine"),
      Right("---\nname: mine\ndescription: >\n  Does a thing.\ndisable-model-invocation: true\nlicense: MIT\n---\n# Body\n---\nkept\n"))

  test("normalize adds a missing name, and refuses a file with no front matter or no description"):
    assertEquals(ExportSkills.normalize("---\ndescription: d\n---", "n"),
      Right("---\nname: n\ndescription: d\ndisable-model-invocation: true\n---"))
    assertEquals(ExportSkills.normalize("# no front matter\n", "n"), Left("n has no front matter"))
    assertEquals(ExportSkills.normalize("---\nname: n\n---\n", "n"), Left("n has no description"))

  test("field reads a value, a folded value and a quoted one"):
    val text = "---\nlicense: \"Apache-2.0\"\nauthor: >-\n  Some\n  One\nname: x\n---\nbody\n"
    assertEquals(ExportSkills.field(text, "license"), "Apache-2.0")
    assertEquals(ExportSkills.field(text, "author"), "Some One")
    assertEquals(ExportSkills.field(text, "compatibility"), "not stated")
    assertEquals(ExportSkills.field("no front matter", "license"), "not stated")

  test("untag and tag"):
    val tags = "a: hermes-skill\nb: x hermes-skill y\nc: x hermes-skill\nd: x"
    assertEquals(ExportSkills.untag(tags), "b: x y\nc: x\nd: x")
    assertEquals(ExportSkills.tag("b: x\nc: hermes-skill\n", Seq("b", "c", "e")),
      "b: x hermes-skill\nc: hermes-skill\ne: hermes-skill\n")
    assertEquals(ExportSkills.tag("d: x", Seq("e")), "d: x\ne: hermes-skill\n")

  test("externalDirs reads a list and an inline list of the external_dirs block"):
    val config = List("model: x", "skills:", "  external_dirs:", "  - /nix/store/aaa-skills", "  - /nix/store/bbb-other/",
      "display:", "  external_dirs: [/nix/store/ccc-x, /nix/store/aaa-skills]", "top: /nix/store/ddd-no")
    assertEquals(ExportSkills.externalDirs(config),
      // The "]" stays until the caller strips it, so the inline aaa-skills is another entry here.
      List("/nix/store/aaa-skills", "/nix/store/bbb-other/", "/nix/store/ccc-x", "/nix/store/aaa-skills]"))

  test("scanSecrets finds a token, never a placeholder, and names only the place"):
    val root = os.temp.dir()
    os.write(root / "skills" / "hermes" / "a" / "SKILL.md",
      "token ghp_xxxxxxxxxxxxxxxxxxxxxxxx\nexample: sk-ant-example-1234567890\n", createFolders = true)
    assertEquals(ExportSkills.scanSecrets(root / "skills" / "hermes", root), None)
    os.write(root / "skills" / "hermes" / "b" / "notes.md", "\n\nkey: ghp_abcdefghijklmnopqrstuvwxyz\n", createFolders = true)
    assertEquals(ExportSkills.scanSecrets(root / "skills" / "hermes", root), Some("skills/hermes/b/notes.md:3 (1)"))

  test("the waiting line without a token, and silence with nothing to export"):
    val dir = os.temp.dir()
    val noToken = TestKit.piabrota(Seq("export-skills"), env = Map("TOKEN_FILE" -> (dir / "none").toString),
      fakes = Some(tools))
    assertEquals((noToken.exitCode, noToken.out.text()),
      (0, "skills export waiting: the piabrota-hermes App has no installation on piabrota/skills (no token file)\n"))
    os.makeDir(dir / "skills")
    val nothing = TestKit.piabrota(Seq("export-skills"),
      env = Map("DRY_RUN" -> "1", "SKILLS_DIR" -> (dir / "skills").toString, "HERMES_HOME" -> dir.toString),
      fakes = Some(tools))
    assertEquals((nothing.exitCode, nothing.out.text()), (0, ""))
    val noDir = TestKit.piabrota(Seq("export-skills"),
      env = Map("DRY_RUN" -> "1", "SKILLS_DIR" -> (dir / "none").toString, "HERMES_HOME" -> dir.toString),
      fakes = Some(tools))
    assertEquals((noDir.exitCode, noDir.out.text()), (1, "skills export failed: no skills directory\n"))

  test("a dry run copies, normalizes and tags the owner's skills, then stops without a python"):
    assume(Sh.which("git").isDefined, "needs git")
    val root = os.temp.dir(prefix = "export-skills")
    val gitEnv = Map("HOME" -> root.toString, "XDG_CONFIG_HOME" -> root.toString, "GIT_CONFIG_NOSYSTEM" -> "1")
    def git(cwd: os.Path, args: os.Shellable*) = os.proc("git", args).call(cwd = cwd, env = gitEnv, stderr = os.Pipe)
    // The repository piabrota/skills, small: one category, tags and the check script.
    val seed = root / "seed"
    os.write(seed / "skills" / "dev" / "taken" / "SKILL.md", "---\nname: taken\n---\n", createFolders = true)
    os.write(seed / "www" / "tags.txt", "taken: dev\nold: hermes-skill\n", createFolders = true)
    os.write(seed / "scripts" / "check.py", "def f(rel):\n        as_is = rel in AS_IS\n", createFolders = true)
    git(root, "init", "-q", "--bare", "-b", "main", root / "origin.git")
    git(seed, "init", "-q", "-b", "main")
    git(seed, "add", "-A")
    git(seed, "-c", "user.name=seed", "-c", "user.email=seed@example.com", "commit", "-q", "-m", "seed")
    git(seed, "push", "-q", s"file://$root/origin.git", "main")
    git(root, "clone", "-q", s"file://$root/origin.git", root / "skills-src")
    // Hermes's skills: one made on the box, one bundled, one the repository has, one in a hidden folder.
    val skills = root / "hermes" / "skills"
    os.write(skills / "mine" / "SKILL.md", "---\nname: mine\ndescription: Mine.\nauthor: me\nlicense: MIT\n---\nbody\n",
      createFolders = true)
    os.write(skills / "mine" / "references" / "a.md", "ref\n", createFolders = true)
    os.write(skills / "bundled" / "SKILL.md", "---\ndescription: b\n---\n", createFolders = true)
    os.write(skills / ".bundled_manifest", "bundled:abc\n")
    os.write(skills / "taken" / "SKILL.md", "---\ndescription: t\n---\n", createFolders = true)
    os.write(skills / ".hub" / "hidden" / "SKILL.md", "---\ndescription: h\n---\n", createFolders = true)

    val r = TestKit.piabrota(Seq("export-skills"), env = gitEnv ++ Map(
      "DRY_RUN" -> "1", "SKILLS_DIR" -> skills.toString, "HERMES_HOME" -> (root / "hermes").toString,
      "REPO_DIR" -> (root / "skills-src").toString, "TMPDIR" -> root.toString), fakes = Some(noGh))
    assertEquals((r.exitCode, r.out.text()), (1, "skills export: no python for the checks\n"), r.err.text())
    val src = root / "skills-src"
    assertEquals(os.list(src / "skills" / "hermes").map(_.last).sorted, Seq("README.md", "mine"))
    assertEquals(os.read(src / "skills" / "hermes" / "mine" / "SKILL.md"),
      "---\nname: mine\ndescription: Mine.\ndisable-model-invocation: true\nlicense: MIT\n---\nbody\n")
    assertEquals(os.read(src / "skills" / "hermes" / "mine" / "references" / "a.md"), "ref\n")
    assert(os.read(src / "skills" / "hermes" / "README.md")
      .endsWith("|---|---|---|---|\n| `mine` | Made by Hermes on this box | MIT | me |\n"))
    assertEquals(os.read(src / "www" / "tags.txt"), "taken: dev\nmine: hermes-skill\n")
    assert(os.read(src / "scripts" / "check.py").contains("""rel.startswith("skills/hermes/")"""))
    assertEquals(Sh.out("git", "branch", "--show-current")(using Sh.Opts(cwd = src)), "hermes/skills-export-dry")
