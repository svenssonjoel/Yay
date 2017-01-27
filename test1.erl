-module(test1). 
-export([start/0,client/0,start_server/0, start_client/0]). 

-include_lib("wx/include/wx.hrl"). 
% -compile(export_all). % what is this for ? 

%  Starting from commandline 
%  erl -pa ebin -eval "application:start(myapp)"
%   run in background: -noshell -detached  

% erl -name server@127.0.0.1
% erl -name client@128.0.0.1  

start() ->
    Wx = wx:new(),
    Frame = wxFrame:new(Wx, -1,  "Yay!"),
    wxFrame:show(Frame),
    wxFrame:createStatusBar(Frame),
    wxFrame:setStatusText(Frame,"Initializing.."),
    wxFrame:connect(Frame, close_window),
    

    MainSizer = wxBoxSizer:new(?wxVERTICAL),
    %Sizer = wxDynamicBoxSizer:new(?wxVERTICAL, Frame, 
    %			   [{label, "wxSizer"}]),
    
    % Notebook = wxNotebook:new(Frame, 1, [{style, ?wxBK_DEFAULT}]),
    
    %ListCtrl = wxListCtrl:new(Notebook, [{style, ?wxLC_LIST}]),
    ListCtrl = wxListCtrl:new(Frame, [{style, ?wxLC_LIST}]),
    
%    [wxListCtrl:insertItem(ListCtrl, Int, "Item "++integer_to_list(Int)) ||
%	Int <- lists:seq(0,50)],

    wxListCtrl:connect(ListCtrl, command_list_item_selected, []),
    
    % TODO: Figure out how to work with sizers... 
    %wxSizer:add(Sizer, ListCtrl, [{flag, ?wxEXPAND}]),
    %wxSizer:add(MainSizer, Sizer, [{flag, ?wxEXPAND}, {proportion, 1}]),
    wxSizer:add(MainSizer, ListCtrl, [{flag, ?wxEXPAND}, {proportion, 1}]),
    wxFrame:setSizer(Frame,MainSizer), 

    % TODO: I have no idea what a sizer is.. read wx manual. 
    %MainSizer = wxStaticBoxSizer:new(?wxVERTICAL, Frame,
    %				     [{label, "wxListCtrl"}]),
    %wxSizer:add(MainSizer, ListCtrl, [{proportion, 1},
    %				      {flag, ?wxEXPAND}]),
    %wxNotebook:addPage(Notebook, ListCtrl, "List", []),

    %T = self(), % Get the process id 
    %spawn(fun() -> messages(T) end), 

    loop(Frame, {[],erlang:monotonic_time(),erlang:monotonic_time()}, ListCtrl).

%messages(T) -> 
%    T ! hello, 
%    timer:sleep(1000), 
%    messages(T). 

% TODO: how to share a datastructure between two processes ?
%       To break out a ping process that checks if clients are alive. 
%       Answer: Mnesia ?? 
% TODO: The state carried in the loop should be a record. 

loop(Frame, {State,TimeStamp,PingTimeStamp}, ListCtrl) ->
    io:format("~p ~n", [State]),
    NewTime = erlang:monotonic_time(),
    % io:format("~p ~n", [NewTime - TimeStamp]), 

    % Go through the state and send a ping to each of the connected clients. 
    % should be a map like construct.
    
    % io:format("~p ~n", [NewTime - PingTimeStamp]), 
    NewPingTimeStamp = 
	if 
	    (NewTime - PingTimeStamp) > (2 * 1000000000) ->  
		lists:map(fun({Pid,_}) -> Pid ! {ping, self()} end, State),
		NewTime;
	    true -> PingTimeStamp
	end,

    % Clean out clients that seem to have died.
    % TODO: base this on a status field for each of the clients in 
    %       the datastructre.
    %       Possible statuses: running, unresponsive, dead 
    %       If a certain time passed without the client responding to a ping 
    %       a running client should be marked unresponsive. 
    %       After yet more time it should be marked dead. 
    %       dead clients should be removed. 
    NewState = lists:filter(fun({_,Time}) -> 
				    NewTime - Time < 5 * 1000000000 
			    end, State), 
    Dead = lists:filter(fun({_,Time}) -> 
				NewTime - Time >= 5 * 1000000000 
			end, State), 
   
    % Woa! the syntax! 
    lists:map(fun({Pid,_}) -> 
		      Name = "client" ++ pid_to_list(Pid), 
		      case wxListCtrl:findItem(ListCtrl,-1,Name) of 
			  -1 -> true;
			  N  -> wxListCtrl:deleteItem(ListCtrl,N)	    
		      end
	      end, Dead), 

    receive
	#wx{event=#wxClose{}} ->
  	    io:format("~p Closing window ~n",[self()]),
  	    wxFrame:destroy(Frame),
	    ok;

	% A new client says hello. add it to datastructure
	{hello, Pid} -> 
	    Pid ! "hello there", % nonsense response for now

	    ItemId = wxListCtrl:getItemCount(ListCtrl),
	    ListItem = wxListItem:new(),
	    wxListItem:setText(ListItem, "Client" ++ pid_to_list(Pid)),
	    % wxListItem:setData(ListItem,3213213), 
			  % This is an alternative 
			  % way to id the item. 
                          % So that different label 
	                  % and id can be used. 
	    wxListItem:setId(ListItem, ItemId+1), 
	    wxListCtrl:insertItem(ListCtrl,ListItem),

	    % Trying to make the window refresh itself after 
	    % adding a list item. But this does not seem to do the 
            % trick. More wx knowledge is needed.
            % Nothing gets drawn in the frame until after a resize action 
            % has been performed on the window. 
	   
            %wxWindow:layout(ListCtrl),
	    %vxWindow:refresh(ListCtrl), 


	    % Now, after adding sizers, these "getParent" calls 
	    % will return the sizer ? 
	    wxWindow:layout(wxWindow:getParent(ListCtrl)),
	    wxWindow:refresh(wxWindow:getParent(ListCtrl)),
	    wxWindow:update(wxWindow:getParent(ListCtrl)),
	    loop(Frame, {[{Pid,NewTime} | NewState],NewTime, NewPingTimeStamp},ListCtrl);

	% A client responds to a ping (refresh the client status) 
	{pong, Pid} -> 
	    % figure out how to extract a field from the datastructure. 
	    % get a new time here and update the last-pong time for this client. 
	    wxFrame:setStatusText(Frame,"RECEIVED PONG"),
	    Pid_ = case lists:keyfind(Pid, 1, NewState) of 
		       {_,_} -> {Pid, NewTime}; 
		       true  -> io:format("ERROR, client not in list")
		   end,
	    State_ = lists:keydelete(Pid,1,NewState),
	    
	    loop(Frame, {[Pid_| State_], NewTime, NewPingTimeStamp},ListCtrl); 
       
	{status, Str} -> 
	    wxFrame:setStatusText(Frame,Str),
	    loop(Frame, {NewState,NewTime,NewPingTimeStamp},ListCtrl);
	
	% Matches any message 
	Msg ->
	    io:format("Got ~p ~n", [Msg]),
	    loop(Frame,{NewState,NewTime,NewPingTimeStamp},ListCtrl)

    % If no message go back through loop after specified time (?) 
    after 100 ->
	    wxFrame:setStatusText(Frame,"IDLE"),
	    loop(Frame,{NewState,NewTime,NewPingTimeStamp},ListCtrl)
	     
    end.


% TODO: Put client in a different module. (Can I do that?)
%       The client has no dependency on wx and will run on platform 
%       where wx does not exist. (Does this matter?) 

client() ->
    [Name, Server, _ ] = readlines("config.txt"),
    io:format("read: ~p ~p ~n", [Name, Server]), 
    
    % binary_to_existing_atom did not work here. 
    Serv = erlang:binary_to_atom(Server,utf8), % the server id atom 
    Nom  = erlang:binary_to_list(Name),
    {server, Serv} ! {hello, self()},
    {server, Serv} ! {status, Nom},
    client_loop(). % enter client loop 
    
    
client_loop() ->
    receive 
	% someone (probably server) is asking if client is still there
	{ping, Pid} ->
	    io:format("Client ~p is still running ~n", [self()]),
	    Pid ! {pong, self()},
	    client_loop();

	% end the client process. 
	stop -> 
	    io:format("Stopping process ~p ~n",[self()]), 
	    ok; 
	
	% Unknown message... 
	Msg ->
	    io:format("Got ~p ~n", [Msg]),
	    client_loop()
    after 1000 -> 
	    client_loop()
    end. 

	      
readlines(FileName) ->
    {ok, Data} = file:read_file(FileName),
    binary:split(Data, [<<"\n">>], [global]).
	
start_server() ->
    %register is currently a bit unclear to me.. 					       
    register(server,spawn(test1,start,[])).
    

start_client() ->    
    spawn(test1, client, []).
    
% Change the statusbar text
%    wxFrame:setStatusText(Frame,"apa").
 

% Status bar handling. 
%    SB = wxFrame:getStatusBar(Frame),
%    wxStatusBar:pushStatusText(SB, "HELLO"),
%    wxStatusBar:popStatusText(SB).

    





