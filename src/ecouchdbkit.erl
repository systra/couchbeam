%% @author Benoît Chesneau <benoitc@e-engura.org>
%% @copyright 2009 Benoît Chesneau.
%%
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.

-module(ecouchdbkit).
-behaviour(application).
-behaviour(gen_server).
-author('Benoît Chesneau <benoitc@e-engura.org').

-export([start/0, start/2, stop/0, stop/1, open_connection/1]).
-export([init/1, handle_call/3,sup_start_link/0]).
-export([handle_cast/2,code_change/3,handle_info/2,terminate/2]).
-export([json_encode/1, json_decode/1]).
-export([make_request/4, make_request/5, make_request/6, 
         make_request/7, do_reply/1]).

-export([server_info/1, all_dbs/1, db_info/2, create_db/2, delete_db/2,
         uuids/0, uuids/1, uuids/2, next_uuid/0, next_uuid/1, open_doc/3, open_doc/4, 
         save_doc/3, save_doc/4, save_docs/3, save_docs/4, delete_doc/3, 
         query_view/4, query_view/5, query_view/6, is_db/2, 
         all_docs/3, all_docs_by_seq/3]).

         
-include("ecouchdbkit.hrl").
-define(SERVER, ?MODULE).

%% @type node_info() = {Host::string(), Port::int()}
%% @type iolist() = [char() | binary() | iolist()]
%% @type iodata() = iolist() | binary()
%% @type json_string() = atom | binary()
%% @type json_number() = integer() | float()
%% @type json_array() = [json_term()]
%% @type json_object() = {struct, [{json_string(), json_term()}]}
%% @type json_term() = json_string() | json_number() | json_array() |
%%                     json_object()


start() ->
    ecouchdbkit_sup:start_link().
    
stop() ->
    ecouchdbkit_sup:stop().

start(_Type, _StartArgs) ->
    start().
     
stop(_Reason) ->
    stop().
    
sup_start_link() ->
    gen_server:start_link({local, ecouchdbkit}, ecouchdbkit, [], []).
    
    
%% @spec open_connection(node()) -> ok
%% @type node() = {NodeName::atom()|string(), Hostname::string(), Port::integer()}
%% @doc When you use ecouchdbkit as an application (OTP mode) you could setup the 
%% connection and open a gen_server that will be supervised. It allow you
%% for now to set once the CouchDB node and reuse settings. In a future version it will
%% be possible to setup loadbalancing and such things.
open_connection({NodeName, {Host, Port}}) ->
    gen_server:call(ecouchdbkit, {open_connection, {NodeName, {Host, Port}}}).
    
%% @spec json_encode(V::json_term()) -> iolist()
%% @doc Encode to json
json_encode(V) ->
    ecouchdbkit_mochijson2:encode(V).
    
%% @spec json_decode(V::iolist()) -> json_term()
%% @doc decode from json string
json_decode(V) ->
    ecouchdbkit_mochijson2:decode(V).
    
    
%% server operations 
server_info(NodeName) ->
    Resp = make_request(NodeName, 'GET', "/", []),
    {Resp1} = do_reply(Resp),
    Resp1.

uuids() ->
    gen_server:call(ecouchdbkit, uuids).
       
uuids(Count) -> 
    gen_server:call(ecouchdbkit, {uuids, Count}).

uuids(NodeName, Count) ->
    Resp = make_request(NodeName, 'GET', "/_uuids", [], [{"count", Count}]),
    {[{<<"uuids">>, Uuids}]} = do_reply(Resp),
    Uuids. 
          
next_uuid() ->
    gen_server:call(ecouchdbkit, next_uuid).
    
next_uuid(NodeName) ->
    case lists:member(ecouchdbkit_uuids, ets:all()) of
    true ->
        case ets:lookup(ecouchdbkit_uuids, uuids) of
        [] -> new_uuids1(NodeName);
        [{uuids, []}] -> new_uuids1(NodeName);
        [{uuids, [Id2|Uuids2]}] ->
        ets:insert(ecouchdbkit_uuids, {uuids, Uuids2}),
        Id2
        end;
    false ->
        ets:new(ecouchdbkit_uuids, [named_table, public, ordered_set]),
        next_uuid(NodeName)
    end.
    
    
%% @spec all_dbs(NodenName::atom()|node_info()) -> list()
%% @doc fetch list of all dbs
all_dbs(NodeName) ->
    Resp = make_request(NodeName, 'GET', "/_all_dbs", []),
    do_reply(Resp).
    
    
%% db operations   
    
%% @spec db_info(NodeName::atom()|node_info(), DbName::string()) -> list()
%% @doc fetch information of Database
db_info(NodeName, DbName) ->
    Resp = make_request(NodeName, 'GET', "/" ++ DbName, []),
    do_reply(Resp).
    
    
%% @spec create_db(NodeName::atom()|node_info(), DbName::string()) -> ok
%% @doc create a database with DbName
create_db(NodeName, DbName) ->
    Resp = make_request(NodeName, 'PUT', "/" ++ DbName, []),
    do_reply(Resp).
    
%% @spec delete_db(NodeName::atom()|node_info(), DbName::string()) -> ok
%% @doc delete a database with dbname
delete_db(NodeName, DbName) ->
    Resp = make_request(NodeName, 'DELETE', "/" ++ DbName, []),
    do_reply(Resp).
  
%% @spec is_db(NodeName::atom()|node_info(), DbName::string()) -> true|false
%% @doc If database exist in the node returns true
is_db(NodeName, DbName) ->
    AllDbs = all_dbs(NodeName),
    lists:member(?l2b(DbName), AllDbs).

%% document operations

%% @spec open_doc(NodeName::atom()|node_info(), DbName::string(), DocId::string()) -> json_object()
%% @doc open a doc with DocID
open_doc(NodeName, DbName, DocId) ->
    open_doc(NodeName, DbName, DocId, nil).
    
%% @spec open_doc(NodeName::atom()|node_info(), DbName::string(), DocId::string(), Rev::string()) -> json_object()
%% @doc open a doc with DocId for specific revision
open_doc(NodeName, DbName, DocId, Rev) ->
    Path = "/" ++ DbName ++ "/" ++ DocId,
    Resp = case Rev of
        nil -> 
            make_request(NodeName, 'GET', Path, []);
        _Rev ->
            make_request(NodeName, 'GET', Path, [], [{"rev", Rev}])
        end,
    do_reply(Resp).
    
%% @spec save_doc(NodeName::atom()|node_info(), DbName::string(), Doc::json_object()) -> json_object() 
%% @doc save a doc. If Id don't exist it will be created, 
%% If _id and _rev are in Doc object, document will be updated
save_doc(NodeName, DbName, Doc) ->
    {Props} = Doc,
    DocId = case proplists:get_value(<<"_id">>, Props) of
    undefined -> 
        case NodeName of
        {_, _} -> next_uuid(NodeName);
        _ -> next_uuid()
        end;
    Id1 -> Id1
    end,
    save_doc(NodeName, DbName, DocId, Doc).
    
%% @spec save_doc(NodeName::atom()|node_info(), DbName::string(), Doc::json_object(), DocId::string) -> json_object() 
%% @doc save a do with DocId. 
save_doc(NodeName, DbName, DocId, Doc) ->
    Path = "/" ++ DbName ++ "/" ++ encode_docid(DocId),
    Body = ecouchdbkit:json_encode(Doc),
    Resp = make_request(NodeName, 'PUT', Path, Body, [], []),
    do_reply(Resp).
    
%% @spec save_docs(NodeName::atom()|node_info(), DbName::string(), Docs::json_array()) -> json_object() 
%% @doc bulk update
save_docs(NodeName, DbName, Docs) ->
    save_docs(NodeName, DbName, Docs, []).
  
%% @spec save_docs(NodeName::atom()|node_info(), DbName::string(), Docs::json_array(), opts: lists()) -> json_object() 
%% @doc bulk update with options, currently support only all_or_nothing.     
save_docs(NodeName, DbName, Docs, Opts) ->
    Docs1 = [maybe_docid(NodeName, Doc) || Doc <- Docs],
    JsonObj = case proplists:get_value(all_or_nothing, Opts, false) of
    true -> {[{<< "all_or_nothing">>, true}, {<<"docs">>, Docs1}]};
    false -> {[{<<"docs">>, Docs1}]}
    end,    
    Body = ecouchdbkit:json_encode(JsonObj),
    Path = "/" ++ DbName ++ "/_bulk_docs",
    Resp = make_request(NodeName, 'POST', Path, Body, [], []),
    do_reply(Resp).
    

%% @spec delete_doc(NodeName::atom()|node_info(), DbName::string(), Doc::json_object()) -> json_object() 
%% @doc delete a document
delete_doc(NodeName, DbName, {DocProps}) ->
    Doc1 = {[{<<"_deleted">>, true}|DocProps]},
    save_doc(NodeName, DbName, Doc1).

%% @spec all_docs(NodeName::atom()|node_info(), DbName::string(), Params::list()) -> json_object()
%% @doc This method has the same behavior as a view. Return all docs
all_docs(NodeName, DbName, Params) ->
    Path = io_lib:format("/~s/_all_docs", [DbName]),
    fetch_view(NodeName, Path, Params).
    
%% @spec all_docs_by_seq(NodeName::atom()|node_info(), DbName::string(), Params::list()) -> json_object()
%% @doc This method has the same behavior as a view. 
%% Return an updated list of all documents.
all_docs_by_seq(NodeName, DbName, Params) ->
    Path = io_lib:format("/~s/_all_docs_by_seq", [DbName]),
    fetch_view(NodeName, Path, Params).
    

%% @spec query_view(NodeName::atom()|node_info(), DbName::string(), 
%%                      DName::design_name(),ViewName::view_name()) -> json_object()
%% @type design_name() = string()
%% @type view_name() = string()
%% @doc query a view and return all results
query_view(NodeName, DbName, DName, ViewName) ->
    query_view(NodeName, DbName, DName, ViewName, []).

%% @spec query_view(NodeName::atom()|node_info(), DbName::string(), 
%%                  DName::design_name(),ViewName::view_name(),
%%                  Params::view_params()) -> json_object()
%% @type view_params() = proplist()
%% @doc query a view and return results depending on params   
query_view(NodeName, DbName, DName, ViewName, Params) ->
    Path = io_lib:format("/~s/_design/~s/_view/~s", [DbName, DName, ViewName]),
    fetch_view(NodeName, Path, Params).

%% @spec query_view(NodeName::atom()|node_info(), DbName::string(), 
%%                  DName::design_name(),ViewName::view_name(),
%%                  Params::view_params(), Fun::view_fun()) -> json_object()
%% @type view_fun() = fun_arity_0() | {fun_arity_1(), initial_state()} 
%% @doc query a view and return results depending on params, fun could be specfied
%% to pare the incoming view. See parse_incoming_view in examples.
%% 
query_view(NodeName, DbName, DName, ViewName, Params, Fun) ->
    Path = io_lib:format("/~s/_design/~s/_view/~s", [DbName, DName, ViewName]),
    fetch_view(NodeName, Path, Params, Fun).
    
%% @spec do_reply(Resp::term()) -> term()
%% @doc make transformation on final http response
do_reply(Resp) ->
    case Resp of
    {error, Reason} -> throw(Reason);
    {json, {[{<<"ok">>, true}]}} -> ok;
    {json, {[{<<"ok">>, true}|Res]}} -> {ok, {Res}};
    {json, Obj} -> Obj;
    Other -> Other
    end.
    
%% @spec make_request(NodeName::atom()|node_info(),Method::string(), 
%%                  Path::string(),Headers::headers()) -> term()
%% @type headers() = [tuple()]
%% @doc function used to create and send request.
make_request(NodeName, Method, Path, Headers) ->
    make_request(NodeName, Method, Path, nil, Headers, []).
    
make_request(NodeName, Method, Path, Headers, Params) ->
    make_request(NodeName, Method, Path, nil, Headers, Params).
    
make_request({_Host,_Port}=Node, Method, Path, Body, Headers, Params) ->
    ecouchdbkit_client:send_request(Node, Method, Path, Body, Headers, Params);
    
make_request(NodeName, Method, Path, Body, Headers, Params) ->
    case gen_server:call(ecouchdbkit, {get, NodeName}) of
    {error, Reason} -> 
        {error, Reason};
    Pid -> 
        gen_server:call(Pid, {request, Method, Path, Body, Headers, Params})
    end.

make_request({_Host,_Port}=Node, Method, Path, Body, Headers, Params, Fun) ->
    ecouchdbkit_client:send_request(Node, Method, Path, Body, Headers, Params, Fun);
    
make_request(NodeName, Method, Path, Body, Headers, Params, Fun) ->
    case gen_server:call(ecouchdbkit, {get, NodeName}) of
    {error, Reason} -> 
        {error, Reason};
    Pid -> 
        gen_server:call(Pid, {request, Method, Path, Body, Headers, Params, Fun})
    end.    
    
%% gen servers calls  
init([]) ->
    Tid = ets:new(ecouchdbkit_uuids, [public, ordered_set]),
    State = #ecouchdbkit_srv{
        ets_tid=Tid
    },
    {ok, State}.
    

handle_call({get, NodeName}, _From, #ecouchdbkit_srv{nodes=Nodes}=State) ->
    AllNodes = supervisor:which_children(ecouchdbkit_nodes),
    ErrorMsg = lists:flatten(
        io_lib:format("No couchdb node configured for ~p.", [NodeName])),
    R = case find_node(AllNodes, NodeName) of
    false ->
        case proplists:get_value(NodeName, Nodes) of
        undefined ->
            {error, {unknown_couchdb_node, ?l2b(ErrorMsg)}};
        Node ->
            #couchdb_node{
                host=Host,
                port=Port
            } = Node,
            {Pid, _} = open_connection1({NodeName, {Host, Port}}, Nodes),
            Pid
        end;
    Pid -> Pid
    end,
    {reply, R, State};
    
handle_call({open_connection, {NodeName, {Host, Port}}}, _From, #ecouchdbkit_srv{nodes=Nodes}=State) ->
    {_, Nodes1} = open_connection1({NodeName, {Host, Port}}, Nodes),
    {reply, ok, State#ecouchdbkit_srv{nodes=Nodes1}};
    
handle_call(next_uuid, _From, #ecouchdbkit_srv{ets_tid=Tid}=State) ->
    R = case ets:lookup(Tid, uuids) of
    [] -> new_uuid(Tid);
    [{uuids, []}] -> new_uuid(Tid);
    [{uuids, [Id2|Uuids2]}] ->
        ets:insert(Tid, {uuids, Uuids2}),
        Id2
    end,
    {reply, R, State};
    
handle_call(uuids, _From, State) ->
    NewUuid = couchdbkit_util:new_uuid(),
    {reply, NewUuid, State};

handle_call({uuids, Count}, _From, State) ->
    UUIDs = [ couch_util:new_uuid() || _ <- lists:seq(1,Count)],
    {reply, UUIDs, State}.

terminate(_Reason, _State) ->
    ok.
    
handle_cast(Msg, _Server) ->
    exit({unknown_cast_message, Msg}).
    
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.


handle_info(Info, _Server) ->
    exit({unknown_message, Info}).
    
%% Internal API

%% @private
%% @doc function used to fetch view
fetch_view(NodeName, Path, Params) ->
    fetch_view(NodeName, Path, Params, fun ecouchdbkit_client:body_fun/2).
%% @private    
fetch_view(NodeName, Path, Params, Fun) ->
    Resp = case proplists:get_value("keys", Params) of
        undefined -> 
            make_request(NodeName, 'GET', Path, nil, [], Params, Fun);
        Keys ->
            Params1 = proplists:delete("keys", Params),
            Body = ecouchdbkit:json_encode({struct, {<<"keys">>, Keys}}),
            make_request(NodeName, 'POST', Path, Body, [], Params1, Fun)
        end,
    do_reply(Resp).

%% @private
%% Create a ecouchdbkit_client sertver for a nodename if it don't exist
open_connection1({NodeName, {Host, Port}}, Nodes) ->
    NodeName1 = nodename(NodeName),
    Client = {NodeName1,
        {ecouchdbkit_client, start_link, [{Host, Port}]},
        permanent,
        brutal_kill,
        worker,
        [ecouchdbkit_client]},
    Pid = case supervisor:start_child(ecouchdbkit_nodes, Client) of
    {ok, Pid1} -> Pid1;
    {error, {already_started, _}} ->
        %% terminate child and create a new one with settings
        supervisor:terminate_child(ecouchdbkit_nodes, NodeName1),
        supervisor:delete_child(ecouchdbkit_nodes, NodeName1),
        Nodes1 = proplists:delete(NodeName1, Nodes),
        open_connection1({NodeName, {Host, Port}}, Nodes1);
    {error, already_present} ->
        case supervisor:start_child(ecouchdbkit_nodes, Client) of
        {ok, Pid1} -> Pid1;
        {error, already_present} ->
            case supervisor:restart_child(ecouchdbkit_nodes, NodeName1) of
            {ok, Pid1} -> Pid1;
            {error, running} ->
                {error, {already_started, Pid1}} =
                    supervisor:start_child(ecouchdbkit_nodes, Client),
                Pid1
            end
        end
    end,
    Node = {NodeName1, #couchdb_node{host=Host, port=Port}},
    Nodes2 = [Node|proplists:delete(NodeName1, Nodes)],
    {Pid, Nodes2}.
    
new_uuid(Tid) ->
    [Id|Uuids] = ecouchdbkit_util:generate_uuids(1000),
    ets:insert(Tid, {uuids, Uuids}),
    Id.
    
new_uuids1(NodeName) ->
    [Id|Uuids] = uuids(NodeName, "1000"),
    ets:insert(ecouchdbkit_uuids, {uuids, Uuids}),
    Id.
    
encode_docid(DocId) when is_binary(DocId) ->
    ?b2l(DocId);
encode_docid(DocId) when is_list(DocId) ->
    DocId.
    
maybe_docid(NodeName, {DocProps}) ->
    case proplists:get_value(<<"_id">>, DocProps) of
        undefined ->
            DocId = case NodeName of
            {_H, _P} -> next_uuid(NodeName);
            _ -> couchdbkit_util:new_uuid()
            end,
            {[{<<"_id">>, DocId}|DocProps]};
        _DocId ->
            {DocProps}
    end.
    
nodename(N) when is_binary(N) ->
    list_to_atom(?b2l(N));
nodename(N) when is_list(N) ->
    list_to_atom(N);
nodename(N) when is_atom(N) ->
    N.
    
find_node([], _Name) ->
    false;
find_node([Node|R], Name) ->
    {Id, Pid, _, _} = Node,
    if
    Id =:= Name -> 
        Pid;
    true ->
        find_node(R, Name)
    end.