package piabrota.scripts

class HermesCheckTest extends munit.FunSuite:
  test("a word is matched as grep -w does"):
    assert(HermesCheck.hasWord("nix-managed-tripwire  enabled", "tripwire"))
    assert(HermesCheck.hasWord("x inbox_old inbox", "inbox"))
    assert(!HermesCheck.hasWord("inbox_old", "inbox"))
    assert(!HermesCheck.hasWord("gh-refs", "gh-ref"))
