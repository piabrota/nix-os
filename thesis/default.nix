# `thesis`, the toolkit of the wave-forecaster-thesis rig (docs/THESIS.md): sections of a final
# project for the Escola Politécnica of UFRJ, claimed one at a time by writer seats, checked by four
# gates, built to a PDF with pandoc and TeX. POSIX sh, jq, awk and pandoc; no Python, no network, no
# model. `bin/thesis` runs with a PATH of its own tools only, and finds its data in share/thesis
# (THESIS_SHARE).
#
# Template: h0ffmann/forecast-energy-demand, pinned by commit. Only the files that the overlay
# uses are installed (shared/thesis_pack.tex, page.sty, portland.sty, the Poli logo as PDF and the
# main file whose \documentclass line is read), under templates/forecast-energy-demand/pinned. The
# overlay (templates/forecast-energy-demand/overlay) fills the gaps against the UFRJ rules and never
# edits a pinned file. The repository has no licence file; the owner, who wrote it, said to use it.
#
# Citations: pandoc --citeproc with the ABNT author-date CSL of citation-style-language/styles, pinned
# by commit, with one change (see `csl`). coppe.bst, which the template names, is not in TeX Live.
#
# PDF engine: pdfLaTeX from a small texlive.combine. Tectonic needs its bundle from the network. The
# set is what the template, babel (Portuguese hyphenation patterns), TeX Gyre Termes and pandoc's
# output need. pandoc-crossref is not used: its closure is 5.5 GiB (Haskell); filters/thesis.lua
# does the cross-references.
#
# Tests: `nix build .#...thesis.tests.run` (passthru.tests.run, test/run.sh) runs the real command on
# a sample project. No check of the flake runs it.
{ lib
, stdenvNoCC
, makeWrapper
, fetchFromGitHub
, fetchurl
, runCommand
, texlive
, pandoc
, poppler-utils
, jq
, coreutils
, gawk
, gnused
, gnugrep
, findutils
, diffutils
, time
, dash
, shellcheck
}:
let
  template = fetchFromGitHub {
    owner = "h0ffmann";
    repo = "forecast-energy-demand";
    rev = "a9a35ee4223037469c0ed35b22ecf510417de86e";
    hash = "sha256-GbhXCVQso+qclGFZ424rwzWn29aB/ZBsiE2sD4atP78=";
  };

  # The ABNT CSL (author-date, CC BY-SA 3.0) at a pinned commit of citation-style-language/styles.
  # One change, made here and checked by the grep: the surname in the in-text citation is upper case
  # ("(TOLMAN, 2009)"), as NBR 10520 writes a parenthetical citation and as Res. 05/2012 shows. The
  # file says so in a comment, as CC BY-SA asks.
  cslUpstream = fetchurl {
    url = "https://raw.githubusercontent.com/citation-style-language/styles/b0114efe1e24554e4193d52b4af16c434d0ad00b/associacao-brasileira-de-normas-tecnicas.csl";
    hash = "sha256-Tz8urblMMUR2YI4HCsuIklP3AH+74+LCUf/JDiFj6q4=";
  };
  csl = runCommand "abnt-author-date.csl" { nativeBuildInputs = [ gnused gnugrep ]; } ''
    sed -e '/<macro name="author-short">/,/<\/macro>/ s/text-case="capitalize-first"/text-case="uppercase"/' \
        -e '2i <!-- Changed by piabrota/nix-os: in the macro author-short the family name is set in upper case, after NBR 10520 and Res. 05/2012 of the Escola Politecnica. Upstream: citation-style-language/styles at b0114efe, associacao-brasileira-de-normas-tecnicas.csl, CC BY-SA 3.0. -->' \
        ${cslUpstream} > $out
    before=$(grep -c 'text-case="uppercase"' ${cslUpstream})
    [ "$(grep -c 'text-case="uppercase"' $out)" -eq $((before + 1)) ]
  '';

  # What the template, babel and pandoc's output need, and nothing else. `graphics` holds rotating and
  # epsfig; `tools` holds layout, enumerate and longtable; `pgf` is the template's tikz.
  tex = texlive.combine {
    inherit (texlive) scheme-basic
      latex-bin tools graphics amsmath amsfonts babel babel-portuges hyphen-portuguese
      tex-gyre float multirow booktabs caption setspace xcolor hyperref hycolor
      etoolbox footnotehyper bookmark xurl pgf psnfss microtype oberdiek kvoptions
      epstopdf-pkg;
  };

  toolPath = lib.makeBinPath [ jq pandoc tex poppler-utils coreutils gawk gnused gnugrep findutils diffutils time ];
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "thesis";
  version = "1";

  # The tests are not part of what runs: a change to them does not rebuild the toolkit.
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.difference ./. (lib.fileset.unions [ ./default.nix ./test ]);
  };

  nativeBuildInputs = [ makeWrapper ];

  dontBuild = true;

  installPhase = ''
    runHook preInstall
    share=$out/share/thesis
    tpl=$share/templates/forecast-energy-demand
    mkdir -p $out/bin $share $tpl/pinned/pt $tpl/pinned/shared/fig $share/csl
    cp -r profile.json lib filters $share/
    cp -r templates/forecast-energy-demand/overlay templates/forecast-energy-demand/template.json $tpl/
    install -m 0755 thesis $out/bin/thesis
    src=${template}/docs/project
    install -m 0444 $src/pt/project_main.tex $tpl/pinned/pt/project_main.tex
    for f in thesis_pack.tex page.sty portland.sty; do install -m 0444 $src/shared/$f $tpl/pinned/shared/$f; done
    install -m 0444 $src/shared/fig/Polinew-eps-converted-to.pdf $tpl/pinned/shared/fig/
    install -m 0444 ${csl} $share/csl/abnt-author-date.csl
    wrapProgram $out/bin/thesis \
      --set THESIS_SHARE $share \
      --set PATH ${toolPath} \
      --set LC_ALL C.UTF-8 \
      --set LANG C.UTF-8
    runHook postInstall
  '';

  passthru = {
    inherit tex csl;
    tests.run = runCommand "thesis-test"
      {
        nativeBuildInputs = [ jq pandoc tex poppler-utils coreutils gawk gnused gnugrep findutils diffutils time dash shellcheck ];
      }
      ''
        pkg=${finalAttrs.finalPackage}
        cd ${./.}
        shellcheck -x -s sh thesis lib/*.sh test/run.sh
        for f in thesis lib/*.sh test/run.sh; do dash -n "$f"; done
        export THESIS=$pkg/bin/thesis
        export TMPDIR=$(mktemp -d)
        sh ${./test/run.sh} | tee $out
      '';
  };

  meta = {
    description = "Toolkit that writes a UFRJ final project in independent sections, checks four gates and builds the PDF";
    license = lib.licenses.mpl20;
    mainProgram = "thesis";
    platforms = lib.platforms.linux;
  };
})
