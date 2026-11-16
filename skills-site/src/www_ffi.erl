%% File access for www.gleam, so the site needs no package beyond gleam_stdlib.
-module(www_ffi).
-export([read/1, write/2, list_dir/1, is_dir/1, make_dir/1]).

read(Path) ->
    case file:read_file(Path) of
        {ok, Bin} -> {ok, Bin};
        {error, _} -> {error, nil}
    end.

write(Path, Text) -> ok = file:write_file(Path, Text), nil.

list_dir(Path) ->
    {ok, Names} = file:list_dir(Path),
    [unicode:characters_to_binary(N) || N <- Names].

is_dir(Path) -> filelib:is_dir(Path).

make_dir(Path) -> ok = filelib:ensure_path(Path), nil.
