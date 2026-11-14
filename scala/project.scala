// The build of every script of this repository: one Scala Native binary, `piabrota`, with one
// subcommand per script (Main.scala). scala/README.md says how to add one; scala/default.nix builds
// it offline from scala/deps.lock.json. Change a version here, then run `just scala-lock`.
//> using scala 3.10.1
//> using platform native
//> using nativeVersion 0.5.12
//> using nativeMode release-fast
// The trampoline object of nativelib has no .note.GNU-stack, so the linker would mark the stack
// executable, and every thread stack with it: systemd's MemoryDenyWriteExecute then refuses it.
//> using nativeLinking -Wl,-z,noexecstack
//> using options -Werror -Wunused:all -deprecation -feature
//> using dep com.lihaoyi::os-lib::0.11.10
//> using dep com.lihaoyi::upickle::4.4.3
//> using dep org.scala-lang.modules::scala-xml::2.5.0
//> using dep io.github.cquiroz::scala-java-time::2.10.0
//> using exclude lock/*
//> using test.dep org.scalameta::munit::1.3.6
