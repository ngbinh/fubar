%%% -------------------------------------------------------------------
%%% Author  : Sungjin Park <jinni.park@sk.com>
%%%
%%% Description : fubar utility functions. 
%%%
%%% Created : Nov 14, 2012
%%% -------------------------------------------------------------------
-module(fubar).
-author("Sungjin Park <jinni.park@sk.com>").

%%
%% Include files
%%
-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

-include("fubar.hrl").
-include("log.hrl").
-include("props_to_record.hrl").

%%
%% Exported Functions
%%
-export([start/0, stop/0, settings/1,	% application start/stop
		 create/1, set/2, get/2, timestamp/2,	% fubar message handling utility
		 profile/2,	% logging utility
		 apply_all_module_attributes_of/1	% bootstrapping utility
		]).

-record(settings, {log_dir = "priv/log" :: string(),
				   log_max_bytes = 104857600 :: integer(),
				   log_max_files = 10 :: integer()}).

%%
%% API Functions
%%

%% @doc Start application.
%% @sample ok = fubar:start().
-spec start() -> ok | {error, reason()}.
start() ->
	application:load(?MODULE),
	Settings = ?PROPS_TO_RECORD(settings(?MODULE), settings),
	Path = filename:join(Settings#settings.log_dir, io_lib:format("~w", [node()])),
	ok = filelib:ensure_dir(Path++"/"),
	error_logger:add_report_handler(
		log_mf_h, log_mf_h:init(Path, Settings#settings.log_max_bytes, Settings#settings.log_max_files)),
	application:start(?MODULE).

%% @doc Stop application.
%% @sample ok = fubar:stop().
-spec stop() -> ok | {error, reason()}.
stop() ->
	application:stop(ranch).

%% @doc Load settings from the application metadata.
%% @sample Props = fubar:settings(?MODULE).
-spec settings(module()) -> proplist(atom(), term()).
settings(Module) ->
	case application:get_env(?MODULE, Module) of
		{ok, Props} -> Props;
		_ -> []
	end.

%% @doc Create a fubar.
%%      Refer fubar.hrl for field definition.
%% @sample Fubar = fubar:create([{from, "romeo"}, {to, "juliet"}]).
-spec create(proplist(atom(), term())) -> #fubar{}.
create(Props) ->
	set(Props, #fubar{}).

%% @doc Set fields in a fubar.
%%      Refer fubar.hrl for field definition.
%% @sample New = fubar:set([{via, "postman"}], Fubar).
-spec set(proplist(atom(), term()), #fubar{}) -> #fubar{}.
set(Props, Fubar=#fubar{}) ->
	Base = ?PROPS_TO_RECORD(Props, fubar, Fubar)(),
	Now = now(),
	Base#fubar{
		origin = stamp(Base#fubar.origin, Now),
		from = stamp(Base#fubar.from, Now),
		to = stamp(Base#fubar.to, Now),
		via = stamp(Base#fubar.via, Now)
	}.

%% @doc Get a field or fields in a fubar.
%%      Refer fubar.hrl for field definition.
%% @sample ["romeo", "juliet"] = fubar:get([from, to], Fubar).
%%         "postman" = fubar:get(via, Fubar).
-spec get(atom() | [atom()], #fubar{}) -> any() | [any()].
get([], #fubar{}) ->
	[];
get([Field | Rest], Fubar=#fubar{}) ->
	[get(Field, Fubar) | get(Rest, Fubar)];
get(id, #fubar{id=Value}) ->
	Value;
get(origin, #fubar{origin={Value, _}}) ->
	Value;
get(from, #fubar{from={Value, _}}) ->
	Value;
get(to, #fubar{to={Value, _}}) ->
	Value;
get(via, #fubar{via={Value, _}}) ->
	Value;
get(ttl, #fubar{ttl=Value}) ->
	Value;
get(payload, #fubar{payload=Value}) ->
	Value;
get(_, _=#fubar{}) ->
	undefined.

%% @doc Get timestamp of a field or fields in a fubar.
%%      origin, from, to, via fields can be checked.
%% @sample T = fubar:timestamp(via, Fubar).
-spec timestamp(atom() | [atom()], #fubar{}) -> timestamp() | undefined.
timestamp([], #fubar{}) ->
	[];
timestamp([Field | Rest], Fubar=#fubar{}) ->
	[get(Field, Fubar) | get(Rest, Fubar)];
timestamp(origin, #fubar{origin={_, Value}}) ->
	Value;
timestamp(from, #fubar{from={_, Value}}) ->
	Value;
timestamp(to, #fubar{to={_, Value}}) ->
	Value;
timestamp(via, #fubar{via={_, Value}}) ->
	Value;
timestamp(_, #fubar{}) ->
	undefined.

%% @doc Leave profiling log.
%% @sample fubar:profile(?MODULE, Fubar).
-spec profile(module(), #fubar{}) -> ok.
profile(Module, #fubar{id=Id, origin={Origin, T1}, from={From, T2}, to={To, T3}, via={Via, T4}}) ->
	Now = now(),
	?INFO([{'PROFILE', Module},
		   {"id", Id},
		   {"since origin", Origin, timer:now_diff(Now, T1)},
		   {"since from", From, timer:now_diff(Now, T2)},
		   {"since to", To, timer:now_diff(Now, T3)},
		   {"since via", Via, timer:now_diff(Now, T4)}]).

%% @doc Get all the attributes of a name in current runtime environment and invoke.
%% The attributes must be a function form, i.e {M, F, A}, {F, A} or F where M must
%% be a module name, F must be a function name and A must be a list of arguments.
apply_all_module_attributes_of({Name, Args}) ->
	[Result || {Module, Attrs} <- all_module_attributes_of(Name),
			   Result <- lists:map(fun(Attr) ->
									   case Attr of
										   {M, F, A} ->
											   {{M, F, A}, apply(M, F, A)};
										   {F, A} ->
											   {{Module, F, A}, apply(Module, F, A)};
										   F ->
											   {{Module, F, Args}, apply(Module, F, Args)}
									   end
								   end, Attrs)];
apply_all_module_attributes_of(Name) ->
	apply_all_module_attributes_of({Name, []}).

all_module_attributes_of(Name) ->
	Modules = lists:append([M || {App, _, _}   <- application:loaded_applications(),
								 {ok, M} <- [application:get_key(App, modules)]]),
	lists:foldl(fun(Module, Acc) ->
						case lists:append([Attr || {N, Attr} <- module_attributes_in(Module),
														 N =:= Name]) of
							[] ->
								Acc;
							Attr ->
								[{Module, Attr} | Acc]
						end
				end, [], Modules).

module_attributes_in(Module) ->
	case catch Module:module_info(attributes) of
		{'EXIT', {undef, _}} ->
			[];
		{'EXIT', Reason} ->
			exit(Reason);
		Attributes ->
			Attributes
	end.

%%
%% Local Functions
%%
stamp({Value, T}, _Now) ->
	{Value, T};
stamp(Value, Now) ->
	{Value, Now}.

%%
%% Tests
%%
-ifdef(TEST).
-endif.