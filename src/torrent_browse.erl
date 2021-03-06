-module(torrent_browse).

-export([search/5]).


-include("../include/torrent.hrl").

% The UI "age" thing has a reverse order compared to the DB
% "timestamp" field.
search(Pattern, Max, Offset, "age", asc) ->
    search(Pattern, Max, Offset, "timestamp", desc);
search(Pattern, Max, Offset, "age", desc) ->
    search(Pattern, Max, Offset, "timestamp", asc);

% TODO: description as erlang docu
% Input
% 	Pattern = Search pattern name, as list
% 	Max = Max results (integer)
% 	Offset = Offset (integer)
% 	SortField = sort field as list. May contain name, length, age, comments, seeders, leechers, speed
% 	SortDir = atom (asc, desc)
% Output
%   {list of #browse_result records, number of total matching torrents}
search(Pattern, Max, Offset, SortField, SortDir) ->
    Now = util:mk_timestamp(),
	SanatizedSortField = sanatize_sortField(SortField),
	C = sql_conns:request_connection(),
	case Pattern of 
		E when is_list(E), E =/= [] ->
			StartSearch = util:mk_timestamp_us(),
			SQLSearchPattern = "%" ++ E ++ "%",	
			SQLStatement = "select (name, infohash, length, count_comments(name), " ++ 
									"$1 - timestamp, count_seeders(infohash), count_leechers(infohash), " ++ 
									"count_downspeed(infohash)) from torrents "++ 
									"where name ilike $2 order by " ++ SanatizedSortField ++ " 
									" ++ atom_to_list(SortDir) ++ " limit $3 offset $4",
			{_, _, MatchingTorrents} = pgsql:equery(C, SQLStatement, [Now, SQLSearchPattern, Max, Offset]),
			TotalCountStatement = "select (count(*)) from torrents where name ilike $1",
			{_, _, [{TotalMatchingTorrents}]} = pgsql:equery(C, TotalCountStatement, [SQLSearchPattern]),
			collectd:set_gauge(delay, torrent_search, [(util:mk_timestamp_us() - StartSearch) / 1000000]);
		_ ->
			StartSearch = util:mk_timestamp_us(),
			SQLStatement = "select (name, infohash, length, count_comments(name), " ++
							"$1 - timestamp, count_seeders(infohash), count_leechers(infohash), " ++
							"count_downspeed(infohash)) from torrents order by " ++ SanatizedSortField ++ " 
							" ++ atom_to_list(SortDir) ++	" limit $2 offset $3", 
			{_, _, MatchingTorrents} = pgsql:equery(C, SQLStatement, [Now, Max, Offset]),
			TotalCountStatement = "select (count(*)) from torrents",
			{_, _, [{TotalMatchingTorrents}]} = pgsql:equery(C, TotalCountStatement),
			collectd:set_gauge(delay, torrent_search, [(util:mk_timestamp_us() - StartSearch) / 1000000])
	end,
	sql_conns:release_connection(C),
	Result = lists:flatmap(fun(X) -> 
					{{Name, InfoHash, Length, CommentCount, Age, Seeders, Leechers, Downspeed}} = X, 
					[#browse_result{
						name = Name,
						id = InfoHash,
						length = Length,
						comments = CommentCount,
						age = Age,
						seeders = Seeders,
						leechers = Leechers,
						speed = Downspeed}]
				  end, 
			MatchingTorrents),
	{Result, TotalMatchingTorrents}.


sanatize_sortField(SortField) when SortField =:= "comments" ->
	"count_comments(name)";
sanatize_sortField(SortField) when SortField =:= "leechers" ->
	"count_seeders(infohash)";
sanatize_sortField(SortField) when SortField =:= "seeders" ->
	"count_seeders(infohash)";
sanatize_sortField(SortField) when SortField =:= "speed" ->
	"count_downspeed(infohash)";
sanatize_sortField(SortField) when SortField =:= "length" ->
	"length";
sanatize_sortField(SortField) when SortField =:= "name" ->
	"name";
sanatize_sortField(_)  ->
	"timestamp".
