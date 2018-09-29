%% Copyright (c) 2018 EMQ Technologies Co., Ltd. All Rights Reserved.
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

-module(emqx_client_SUITE).

-compile(export_all).
-compile(nowarn_export_all).

-import(lists, [nth/2]).

-include("emqx_mqtt.hrl").

-include_lib("eunit/include/eunit.hrl").

-include_lib("common_test/include/ct.hrl").

-define(TOPICS, [<<"TopicA">>, <<"TopicA/B">>, <<"Topic/C">>, <<"TopicA/C">>,
                 <<"/TopicA">>]).

-define(WILD_TOPICS, [<<"TopicA/+">>, <<"+/C">>, <<"#">>, <<"/#">>, <<"/+">>,
                      <<"+/+">>, <<"TopicA/#">>]).

all() ->
    [
        request_response_test
    ].

groups() ->
    [{mqttv4, [non_parallel_tests],
      [basic_test,
       will_message_test,
       zero_length_clientid_test,
       offline_message_queueing_test,
       overlapping_subscriptions_test,
       %% keepalive_test,
       redelivery_on_reconnect_test,
       %% subscribe_failure_test,
       dollar_topics_test]},
     {mqttv5, [non_parallel_tests],
      [request_response_test]}
].

init_per_suite(Config) ->
    emqx_ct_broker_helpers:run_setup_steps(),
    Config.

end_per_suite(_Config) ->
    emqx_ct_broker_helpers:run_teardown_steps().

request_response_test(_Config) ->
    {ok, Requester1, _} = emqx_client:start_link([{proto_ver, v5},
                                {properties, #{ 'Request-Response-Information' => 1}}]),
    {ok, Responser1, _} = emqx_client:start_link([{proto_ver, v5},
                                {properties, #{ 'Request-Response-Information' => 1}}]),
    {ok, ResponseTopic1} = emqx_client:sub_response_topic(Responser1, false, ?QOS_2, <<"request_response_test">>),
    ct:log("ResponseTopic: ~p",[ResponseTopic1]),
    ok = emqx_client:def_response(Responser1, <<"ResponseTest">>),
    {ok, <<"ResponseTest">>} = emqx_client:request(Requester1, <<"request_response_test">>, <<"request_payload">>, ?QOS_2),
    ok = emqx_client:def_response(Responser1, fun(<<"request_payload">>) ->
                                                     <<"ResponseFunctionTest">>;
                                                (_) ->
                                                     <<"404">>
                                             end),
    {ok, <<"ResponseFunctionTest">>} = emqx_client:request(Requester1, <<"request_response_test">>, <<"request_payload">>, ?QOS_2),
    {ok, <<"404">>} = emqx_client:request(Requester1, <<"request_response_test">>, <<"invalid_request">>, ?QOS_2),
    ok = emqx_client:disconnect(Responser1),
    ok = emqx_client:disconnect(Requester1),

    {ok, Requester2, _} = emqx_client:start_link([{proto_ver, v5},
                                {properties, #{ 'Request-Response-Information' => 1}}]),
    {ok, Responser2, _} = emqx_client:start_link([{proto_ver, v5},
                                {properties, #{ 'Request-Response-Information' => 1}}]),
    {ok, ResponseTopic2} = emqx_client:sub_response_topic(Responser2, false, ?QOS_1, <<"request_response_test">>),
    ct:log("ResponseTopic: ~p",[ResponseTopic2]),
    ok = emqx_client:def_response(Responser2, <<"ResponseTest">>),
    {ok, <<"ResponseTest">>} = emqx_client:request(Requester2, <<"request_response_test">>, <<"request_payload">>, ?QOS_1),
    ok = emqx_client:def_response(Responser2, fun(<<"request_payload">>) ->
                                                     <<"ResponseFunctionTest">>;
                                                (_) ->
                                                     <<"404">>
                                             end),
    {ok, <<"ResponseFunctionTest">>} = emqx_client:request(Requester2, <<"request_response_test">>, <<"request_payload">>, ?QOS_1),
    {ok, <<"404">>} = emqx_client:request(Requester2, <<"request_response_test">>, <<"invalid_request">>, ?QOS_1),
    ok = emqx_client:disconnect(Responser2),
    ok = emqx_client:disconnect(Requester2),

    {ok, Requester3, _} = emqx_client:start_link([{proto_ver, v5},
                                {properties, #{ 'Request-Response-Information' => 1}}]),
    {ok, Responser3, _} = emqx_client:start_link([{proto_ver, v5},
                                {properties, #{ 'Request-Response-Information' => 1}}]),
    {ok, ResponseTopic3} = emqx_client:sub_response_topic(Responser3, false, ?QOS_0, <<"request_response_test">>),
    ct:log("ResponseTopic: ~p",[ResponseTopic3]),
    ok = emqx_client:def_response(Responser3, <<"ResponseTest">>),
    {ok, <<"ResponseTest">>} = emqx_client:request(Requester3, <<"request_response_test">>, <<"request_payload">>, ?QOS_0),
    ok = emqx_client:def_response(Responser3, fun(<<"request_payload">>) ->
                                                     <<"ResponseFunctionTest">>;
                                                (_) ->
                                                     <<"404">>
                                             end),
    {ok, <<"ResponseFunctionTest">>} = emqx_client:request(Requester3, <<"request_response_test">>, <<"request_payload">>, ?QOS_0),
    {ok, <<"404">>} = emqx_client:request(Requester3, <<"request_response_test">>, <<"invalid_request">>, ?QOS_0),
    ok = emqx_client:disconnect(Responser3),
    ok = emqx_client:disconnect(Requester3).


receive_messages(Count) ->
    receive_messages(Count, []).

receive_messages(0, Msgs) ->
    Msgs;
receive_messages(Count, Msgs) ->
    receive
        {publish, Msg} ->
            receive_messages(Count-1, [Msg|Msgs]);
        Other ->
            ct:log("~p~n", [Other]),
            receive_messages(Count, Msgs)
    after 10 ->
        Msgs
    end.

basic_test(_Config) ->
    Topic = nth(1, ?TOPICS),
    ct:print("Basic test starting"),
    {ok, C, _} = emqx_client:start_link(),
    {ok, _, [2]} = emqx_client:subscribe(C, Topic, qos2),
    {ok, _} = emqx_client:publish(C, Topic, <<"qos 2">>, 2),
    {ok, _} = emqx_client:publish(C, Topic, <<"qos 2">>, 2),
    {ok, _} = emqx_client:publish(C, Topic, <<"qos 2">>, 2),
    ?assertEqual(3, length(receive_messages(3))),
    ok = emqx_client:disconnect(C).

will_message_test(_Config) ->
    {ok, C1, _} = emqx_client:start_link([{clean_start, true},
                                          {will_topic, nth(3, ?TOPICS)},
                                          {will_payload, <<"client disconnected">>},
                                          {keepalive, 2}]),
    {ok, C2, _} = emqx_client:start_link(),
    {ok, _, [2]} = emqx_client:subscribe(C2, nth(3, ?TOPICS), 2),
    timer:sleep(10),
    ok = emqx_client:stop(C1),
    timer:sleep(5),
    ?assertEqual(1, length(receive_messages(1))),
    ok = emqx_client:disconnect(C2),
    ct:print("Will message test succeeded").

zero_length_clientid_test(_Config) ->
    ct:print("Zero length clientid test starting"),

    %% TODO: There are some controversies on the situation when
    %%       clean_start flag is true and clientid is zero length.

    %% {error, _} = emqx_client:start_link([{clean_start, false},
    %%                                      {client_id, <<>>}]),
    {ok, _, _} = emqx_client:start_link([{clean_start, true},
                                         {client_id, <<>>}]),
    ct:print("Zero length clientid test succeeded").

offline_message_queueing_test(_) ->
    {ok, C1, _} = emqx_client:start_link([{clean_start, false},
                                          {client_id, <<"c1">>}]),
    {ok, _, [2]} = emqx_client:subscribe(C1, nth(6, ?WILD_TOPICS), 2),
    ok = emqx_client:disconnect(C1),
    {ok, C2, _} = emqx_client:start_link([{clean_start, true},
                                          {client_id, <<"c2">>}]),

    ok = emqx_client:publish(C2, nth(2, ?TOPICS), <<"qos 0">>, 0),
    {ok, _} = emqx_client:publish(C2, nth(3, ?TOPICS), <<"qos 1">>, 1),
    {ok, _} = emqx_client:publish(C2, nth(4, ?TOPICS), <<"qos 2">>, 2),
    timer:sleep(10),
    emqx_client:disconnect(C2),
    {ok, C3, _} = emqx_client:start_link([{clean_start, false},
                                          {client_id, <<"c1">>}]),
    timer:sleep(10),
    emqx_client:disconnect(C3),
    ?assertEqual(3, length(receive_messages(3))).

overlapping_subscriptions_test(_) ->
    {ok, C, _} = emqx_client:start_link([]),
    {ok, _, [2, 1]} = emqx_client:subscribe(C, [{nth(7, ?WILD_TOPICS), 2},
                                                {nth(1, ?WILD_TOPICS), 1}]),
    timer:sleep(10),
    {ok, _} = emqx_client:publish(C, nth(4, ?TOPICS), <<"overlapping topic filters">>, 2),
    timer:sleep(10),

    Num = length(receive_messages(2)),
    ?assert(lists:member(Num, [1, 2])),
    if
        Num == 1 ->
            ct:print("This server is publishing one message for all
                     matching overlapping subscriptions, not one for each.");
        Num == 2 ->
            ct:print("This server is publishing one message per each
                     matching overlapping subscription.");
        true -> ok
    end,
    emqx_client:disconnect(C).

%% keepalive_test(_) ->
%%     ct:print("Keepalive test starting"),
%%     {ok, C1, _} = emqx_client:start_link([{clean_start, true},
%%                                           {keepalive, 5},
%%                                           {will_flag, true},
%%                                           {will_topic, nth(5, ?TOPICS)},
%%                                           %% {will_qos, 2},
%%                                           {will_payload, <<"keepalive expiry">>}]),
%%     ok = emqx_client:pause(C1),
%%     {ok, C2, _} = emqx_client:start_link([{clean_start, true},
%%                                           {keepalive, 0}]),
%%     {ok, _, [2]} = emqx_client:subscribe(C2, nth(5, ?TOPICS), 2),
%%     ok = emqx_client:disconnect(C2),
%%     ?assertEqual(1, length(receive_messages(1))),
%%     ct:print("Keepalive test succeeded").

redelivery_on_reconnect_test(_) ->
    ct:print("Redelivery on reconnect test starting"),
    {ok, C1, _} = emqx_client:start_link([{clean_start, false},
                                          {client_id, <<"c">>}]),
    {ok, _, [2]} = emqx_client:subscribe(C1, nth(7, ?WILD_TOPICS), 2),
    timer:sleep(10),
    ok = emqx_client:pause(C1),
    {ok, _} = emqx_client:publish(C1, nth(2, ?TOPICS), <<>>,
                                  [{qos, 1}, {retain, false}]),
    {ok, _} = emqx_client:publish(C1, nth(4, ?TOPICS), <<>>,
                                  [{qos, 2}, {retain, false}]),
    timer:sleep(10),
    ok = emqx_client:disconnect(C1),
    ?assertEqual(0, length(receive_messages(2))),
    {ok, C2, _} = emqx_client:start_link([{clean_start, false},
                                          {client_id, <<"c">>}]),
    timer:sleep(10),
    ok = emqx_client:disconnect(C2),
    ?assertEqual(2, length(receive_messages(2))).

%% subscribe_failure_test(_) ->
%%     ct:print("Subscribe failure test starting"),
%%     {ok, C, _} = emqx_client:start_link([]),
%%     {ok, _, [2]} = emqx_client:subscribe(C, <<"$SYS/#">>, 2),
%%     timer:sleep(10),
%%     ct:print("Subscribe failure test succeeded").

dollar_topics_test(_) ->
    ct:print("$ topics test starting"),
    {ok, C, _} = emqx_client:start_link([{clean_start, true},
                                         {keepalive, 0}]),
    {ok, _, [1]} = emqx_client:subscribe(C, nth(6, ?WILD_TOPICS), 1),
    {ok, _} = emqx_client:publish(C, << <<"$">>/binary, (nth(2, ?TOPICS))/binary>>,
                                  <<"test">>, [{qos, 1}, {retain, false}]),
    timer:sleep(10),
    ?assertEqual(0, length(receive_messages(1))),
    ok = emqx_client:disconnect(C),
    ct:print("$ topics test succeeded").