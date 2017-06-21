-module(twerl_stream).
-export([
          connect/4,
          handle_connection/2
        ]).

-define(CONTENT_TYPE, "application/x-www-form-urlencoded").

-spec connect(string(), list(), string(), fun()) -> ok | {error, reason}.
connect({post, Url}, Auth, Params, Callback) ->
    %% TODO look into moving this into headers_for_auth
    {Headers, Body} = case twerl_util:headers_for_auth(Auth, {post, Url}, Params) of
                        L when is_list(L) ->
                            {L, Params};
                          {H, L2} ->
                              {H, L2}
                      end,
    io:format(" connect params ~p~n", [Params]),
    case catch httpc:request(post, {Url, Headers, ?CONTENT_TYPE, Body}, [], [{sync, false}, {stream, self}]) of
        {ok, RequestId} ->
            io:format("success connect ~w~n", [RequestId]),
            ?MODULE:handle_connection(Callback, RequestId);
        {error, Reason} ->
            {error, {http_error, Reason}}
    end;

connect({get, BaseUrl}, Auth, Params, Callback) ->
    {Headers, UrlParams} = case twerl_util:headers_for_auth(Auth, {get, BaseUrl}, Params) of
                        L when is_list(L) ->
                            {L, Params};
                          {H, L2} ->
                              {H, L2}
                      end,
    Url = BaseUrl ++ "?" ++ UrlParams,
    case catch httpc:request(get, {Url, Headers}, [], [{sync, false}, {stream, self}]) of
        {ok, RequestId} ->
            ?MODULE:handle_connection(Callback, RequestId);
        {error, Reason} ->
            {error, {http_error, Reason}}
    end.

% TODO maybe change {ok, stream_closed} to an error?
-spec handle_connection(term(), term()) -> {ok, terminate} | {ok, stream_closed} | {error, term()}.
handle_connection(Callback, RequestId) ->
    io:format("handle connection ~w~n", [RequestId]),
    receive
        % stream opened
        {http, {RequestId, stream_start, _Headers}} ->
            io:format("stream opened ~w~n", [RequestId]),
            handle_connection(Callback, RequestId);

        % stream received data
        {http, {RequestId, stream, Data}} ->
            io:format("stream received data ~p~n", [Data]),

            spawn(fun() ->
                DecodedData = twerl_util:decode(Data),
                Callback(DecodedData)
            end),
            handle_connection(Callback, RequestId);

        % stream closed
        {http, {RequestId, stream_end, _Headers}} ->
            io:format("stream closed ~w~n", [RequestId]),
            {ok, stream_end};

        % connected but received error cod
        % 401 unauthorised - authentication credentials rejected
        {http, {RequestId, {{_, 401, _}, _Headers, _Body}}} ->
            {error, unauthorised};

        % 406 not acceptable - invalid request to the search api
        {http, {RequestId, {{_, 406, _}, _Headers, Body}}} ->
            {error, {invalid_params, Body}};

        % connection error
        % may happen while connecting or after connected
        {http, {RequestId, {error, Reason}}} ->
            {error, {http_error, Reason}};

        % message send by us to close the connection
        terminate ->
            {ok, terminate}
    end.
