%%	The contents of this file are subject to the Common Public Attribution
%%	License Version 1.0 (the “License”); you may not use this file except
%%	in compliance with the License. You may obtain a copy of the License at
%%	http://opensource.org/licenses/cpal_1.0. The License is based on the
%%	Mozilla Public License Version 1.1 but Sections 14 and 15 have been
%%	added to cover use of software over a computer network and provide for
%%	limited attribution for the Original Developer. In addition, Exhibit A
%%	has been modified to be consistent with Exhibit B.
%%
%%	Software distributed under the License is distributed on an “AS IS”
%%	basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See the
%%	License for the specific language governing rights and limitations
%%	under the License.
%%
%%	The Original Code is Spice Telephony.
%%
%%	The Initial Developers of the Original Code is 
%%	Andrew Thompson and Micah Warren.
%%
%%	All portions of the code written by the Initial Developers are Copyright
%%	(c) 2008-2009 SpiceCSM.
%%	All Rights Reserved.
%%
%%	Contributor(s):
%%
%%	Andrew Thompson <athompson at spicecsm dot com>
%%	Micah Warren <mwarren at spicecsm dot com>
%%

%% @doc The media manager for handling email.  This starts the email server
%% listener.  The listener passes off to the email_media_session callback.
%% When the email_media_session callback is ready for an email to enter queue, 
%% it sends a message back here for an email_media to be created and queued.
-module(email_media_manager).
-author(spicecsm).

-behaviour(gen_server).

%% API
-export([
	start_link/1,
	start/1,
	stop/0]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
	 terminate/2, code_change/3]).

-ifdef(EUNIT).
-include_lib("eunit/include/eunit.hrl").
-endif.

-include("log.hrl").
-include("smtp.hrl").

-record(state, {
	mails = [] :: [pid()]
}).

-type(state() :: #state{}).
-define(GEN_SERVER, true).
-include("gen_spec.hrl").

%%====================================================================
%% API
%%====================================================================
start_link(Options) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [Options], []).

start(Options) ->
	gen_server:start({local, ?MODULE}, ?MODULE, [Options], []).

stop() ->
	gen_server:call(?MODULE, stop).

%%====================================================================
%% gen_server callbacks
%%====================================================================

%%--------------------------------------------------------------------
%% Function: init(Args) -> {ok, State} |
%%--------------------------------------------------------------------
init([Options]) ->
	process_flag(trap_exit, true),
	build_table(),
	gen_smtp_server:start_link(email_media_session, proplists:get_value(port, Options, 2525)),
    {ok, #state{}}.

%%--------------------------------------------------------------------
%% Function: %% handle_call(Request, From, State) -> {reply, Reply, State} |
%%--------------------------------------------------------------------
handle_call({queue, Mailmap, Headers, Data}, From, #state{mails = Mails} = State) ->
	{ok, Mpid} = email_media:start_link(Mailmap, Headers, Data),
	{reply, ok, State#state{mails = [Mpid | Mails]}};
handle_call(stop, From, State) ->
	?INFO("Received request to stop from ~p", [From]),
	{stop, normal, ok, State};
handle_call(_Request, _From, State) ->
    Reply = ok,
    {reply, Reply, State}.

%%--------------------------------------------------------------------
%% Function: handle_cast(Msg, State) -> {noreply, State} |
%%--------------------------------------------------------------------
handle_cast(_Msg, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% Function: handle_info(Info, State) -> {noreply, State} |
%%--------------------------------------------------------------------
handle_info({'EXIT', From, Reason}, #state{mails = Mails} = State) ->
	Newmail = lists:delete(From, Mails),
	{noreply, State#state{mails = Mails}};
handle_info(_Info, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% Function: terminate(Reason, State) -> void()
%%--------------------------------------------------------------------
terminate(Reason, _State) ->
	?INFO("terminating due to ~p", [Reason]),
    ok.

%%--------------------------------------------------------------------
%% Func: code_change(OldVsn, State, Extra) -> {ok, NewState}
%%--------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%--------------------------------------------------------------------
%%% Internal functions
%%--------------------------------------------------------------------

build_table() ->
	?DEBUG("Buidling table...", []),
	A = util:build_table(mail_map, [
		{attributes, record_info(fields, mail_map)},
		{disc_copies, [node()]}
	]),
	case A of
		{atomic, ok} ->
			?INFO("Writing default data...", []),
			F = fun() ->
				mnesia:write(#mail_map{address = "support@example.com"})
			end,
			mnesia:transaction(F);
		_Else when A =:= copied; A =:= exists ->
			?DEBUG("Copied the table from elsewhere.", []),
			ok;
		_Else ->
			A
	end.

