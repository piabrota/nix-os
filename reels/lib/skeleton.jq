# The empty screenplay of `reel new`: the right shape for 15 or 30 s, every text a TODO that the
# lint refuses. Arguments: $slug, $format (15 or 30).
def beat($id; $t0; $t1; $role; $scene; $tr): {
  id: $id, t_in: $t0, t_out: $t1, role: $role,
  visual: {describe: "TODO: what is on screen", scene: $scene, params: {}},
  text: ["TODO"],
  sound: {music: "on", sfx: []},
  transition: $tr,
  note: ""
};
{
  schema: "reels.screenplay/1",
  slug: $slug,
  title: "TODO",
  format: $format,
  logline: "TODO: one sentence, the whole reel",
  audience: "TODO: who watches, and where",
  language: "TODO",
  loop: false,
  claims: [],
  look: {style: "piabrota"},
  music: {preset: "pulse", bpm: (if $format == 15 then 112 else 96 end)},
  beats: (if $format == 15 then
    [beat("b01"; 0; 2.5; "hook"; "kinetic_text"; "cut"),
     beat("b02"; 2.5; 6; "setup"; "title_card"; "fade"),
     beat("b03"; 6; 10; "turn"; "kinetic_text"; "fade"),
     beat("b04"; 10; 12.8; "payoff"; "bullet_reveal"; "fade"),
     beat("b05"; 12.8; 15; "cta"; "outro_loop"; "fade")]
  else
    [beat("b01"; 0; 2.8; "hook"; "kinetic_text"; "cut"),
     beat("b02"; 2.8; 6.8; "setup"; "title_card"; "fade"),
     beat("b03"; 6.8; 11.3; "setup"; "bullet_reveal"; "fade"),
     beat("b04"; 11.3; 15.3; "turn"; "split_compare"; "fade"),
     beat("b05"; 15.3; 19.8; "proof"; "big_number"; "fade"),
     beat("b06"; 19.8; 23.8; "proof"; "timeline"; "fade"),
     beat("b07"; 23.8; 27.3; "payoff"; "quote"; "fade"),
     beat("b08"; 27.3; 30; "cta"; "outro_loop"; "fade")]
  end)
}
