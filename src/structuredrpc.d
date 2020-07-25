module structuredrpc;

import treeserial;

import std.traits;
import std.meta;

import std.algorithm;
import std.range;

template RPC(Src_) {
	alias Src = Src_;
	struct RPC {
		ubyte id;
	}
}
template RPCSend(Src_) {
	alias Src = Src_;
	enum RPCSend;
}

class RPCError : Exception {
	this(string msg, string file = __FILE__, size_t line = __LINE__) {
		super(msg, file, line);
	}
}

enum rpcIDs(Src, alias symbol)() {
	ubyte next = 0;
	ubyte[] ids = [];
	foreach (mem; getSymbolsByUDA!(symbol, RPC!Src)) {
		alias udas = getUDAs!(mem, RPC!Src);
		static assert(udas.length == 1);
		static if (is(udas[$-1])) {
			assert(next+1 != 0);
			ids ~= next++;
		}
		else {
			ids ~= udas[$-1].id;
			next = udas[$-1].id+1;
		}
	}
	return ids;
}
template rpcByID(Src, alias symbol, ubyte id) {
	import std.algorithm;
	alias rpcByID = getSymbolsByUDA!(symbol, RPC!Src)[rpcIDs!(Src,symbol).countUntil(id)];
}


template RPCParameters(alias f, Connection) {
	alias Params = Parameters!f;
	static if (is(Connection == typeof(null))) {
		alias RPCParameters = Params;
	}
	else static if (is(Params[0] == Connection)) {
		alias RPCParameters = Params[1..$];
	}
	else static if (is(Params[$-1] == Connection)) {
		alias RPCParameters = Params[0..$-1];
	}
	else {
		alias RPCParameters = Params;
	}
}
template RPCConnectionsParam(Connection) {
	static if (is(Connection == typeof(null)))
		alias RPCConnectionsParam = AliasSeq!();
	else
		alias RPCConnectionsParam = Connection[];
}

mixin template MakeRPCReceive(Src, Connection, alias Serializer) {
	import std.meta;
	import std.traits;
	import std.algorithm;
	import treeserial;
	
	template rpcRecv(S:Src) {
		void rpcRecv(const(ubyte)[] data) {
			enum ids = rpcIDs!(Src, typeof(this));
			ubyte msgID = Serializer.deserialize!ubyte(data);
			static foreach(id; ids) {
				if (msgID == id) {
					alias rpc = rpcByID!(Src, typeof(this),id);
					alias Params = Parameters!rpc;
					Params args;
					scope (success)
						rpc(args);
					foreach (i, Param; Params) {
						static if (deserializable!Param) {
							static if (i==Params.length-1)
								alias Attributes = NoLength;
							else
								alias Attributes = AliasSeq!();
							args[i] = Serializer.Subserializer!(Attributes).deserialize!Param(data);
						}
						else throw new RPCError("Parameter \""~Param.stringof~"\" of RPC \""~__traits(identifier, rpc)~"\" cannot be deserialized.  If it is a ConnectionType then you called the wrong rpcRecv (call rpcRecv with a connection).");
					}
				}
			}
		}
		static if (!is(Connection == typeof(null)))
		void rpcRecv(Connection connection, const(ubyte)[] data){//// if (!is(ConnectionType!(RPCSrc, src) == typeof(null))) {
			enum ids = rpcIDs!(Src, typeof(this));
			ubyte msgID = Serializer.deserialize!ubyte(data);
			static foreach(id; ids) {
				if (msgID == id) {
					alias rpc = rpcByID!(Src, typeof(this),id);
					alias Params = RPCParameters!(rpc,Connection);
					Params args;
					scope (success) {
						static if (is(Parameters!rpc[0] == Connection))
							rpc(connection, args);
						else static if (is(Parameters!rpc[$-1] == Connection))
							rpc(args, connection);
						else
							rpc(args);
					}
					foreach (i, Param; Params) {
						static if (deserializable!Param) {
							static if (i==Params.length-1)
								alias Attributes = NoLength;
							else
								alias Attributes = AliasSeq!();
							args[i] = Serializer.Subserializer!(Attributes).deserialize!Param(data);
						}
						else throw new RPCError("Parameter `"~Param.stringof~"` of RPC `"~__traits(identifier, rpcTemplate)~"` cannot be deserialized.");////  If you think this should be the connection type, then for `"~RPCSrc.stringof~"."~__traits(identifier, src)~"` it should be of type `"~ConnectionType!src.stringof~"` (Correct parameter or `SrcType` or src).");
					}
				}
			}
		}
	}
}
mixin template MakeRPCReceive(Src) {
	mixin MakeRPCReceive!(Src, typeof(null), Serializer!());
}
mixin template MakeRPCReceive(Src, alias Serializer) {
	mixin MakeRPCReceive!(Src, typeof(null), Serializer);
}
mixin template MakeRPCReceive(Src, Connection) {
	mixin MakeRPCReceive!(Src, Connection, Serializer!());
}


mixin template MakeRPCSend(Src, Connection, alias Serializer) {
	import std.meta;
	import std.traits;
	import std.algorithm;
	import treeserial;
	
	static foreach (i, rpc; getSymbolsByUDA!(typeof(this), RPC!Src)) {
		mixin(q{
			template }~__traits(identifier, rpc)~q{_send(S:Src) }~"{"~q{
				////alias _ =  Parameters!rpc;// Stops some glitchy "recursive template expansion" compile error.
				void }~__traits(identifier, rpc)~q{_send(RPCConnectionsParam!Connection connections, RPCParameters!(rpc, Connection) args) {
					const(ubyte)[] data = Serializer.serialize!ubyte(rpcIDs!(Src, typeof(this))[i]);
					alias rpcSend = getSymbolsByUDA!(typeof(this), RPCSend!Src)[0];
					scope(success)
						rpcSend(connections, data);
					foreach (i, arg; args) {
						static if (serializable!arg) {
							static if (i==args.length-1)
								alias Attributes = NoLength;
							else
								alias Attributes = AliasSeq!();
							data ~= Serializer.Subserializer!(Attributes).serialize(arg);
						}
						else throw new RPCError("Parameter \""~typeof(arg).stringof~"\" of RPC \""~__traits(identifier, rpc)~"\" cannot be serialized.");
					}
				}
				static if (!is(Connection == typeof(null)))
				void }~__traits(identifier, rpc)~q{_send(Connection connection, RPCParameters!(rpc, Connection) args) }~"{
					"~__traits(identifier, rpc)~"_send([connection], args);
				}
			}"~q{
		});
	}
}
mixin template MakeRPCSend(Src) {
	mixin MakeRPCSend!(Src, typeof(null), Serializer!());
}
mixin template MakeRPCSend(Src, alias Serializer) {
	mixin MakeRPCSend!(Src, typeof(null), Serializer);
}
mixin template MakeRPCSend(Src, Connection) {
	mixin MakeRPCSend!(Src, Connection, Serializer!());
}

unittest {
	pragma(msg, "Compiling Test A");
	import std.stdio;
	writeln("Running Test A");
	import std.exception;
	import std.conv;
	
	enum Src;
	
	string lastMsg = "";
	class A {
		@RPC!Src
		void msg(int x) {
			lastMsg = "msg: "~x.to!string;
		}
		@RPC!Src
		void msg2(float x) {
			lastMsg = "msg2: "~x.to!string;
		}
		mixin MakeRPCReceive!Src;
	}
	A a = new A;
	a.msg(5);
	assert(lastMsg == "msg: 5");
	a.rpcRecv!Src(0 ~ serialize(1));
	assert(lastMsg == "msg: 1");
}
unittest {
	pragma(msg, "Compiling Test B");
	import std.stdio;
	writeln("Running Test B");
	import std.exception;
	import std.conv;
	
	enum Src;
	class Connection {}
	
	string lastMsg = "";
	class A {
		@RPC!Src
		void msg(int x) {
			lastMsg = "msg: "~x.to!string;
		}
		void msg2(float x) {
			lastMsg = "msg2: "~x.to!string;
		}
		@RPC!Src
		void msg2(float x, Connection con) {
			lastMsg = "msg2: remote - "~x.to!string;
		}
		@RPC!Src
		void msg3(Connection con, float x) {
			lastMsg = "msg3: remote - "~x.to!string;
		}
		@RPC!Src
		void msg4(float x) {
			lastMsg = "msg4: remote - "~x.to!string;
		}
		mixin MakeRPCReceive!(Src, Connection);
	}
	A a = new A;
	a.msg(5);
	assert(lastMsg == "msg: 5");
	a.rpcRecv!Src(0 ~ serialize(1));
	assert(lastMsg == "msg: 1");
	assertThrown!Throwable(a.rpcRecv!Src(1 ~ serialize(1.5f)));
	a.rpcRecv!Src(new Connection(), 1 ~ serialize(1f));
	assert(lastMsg == "msg2: remote - 1");
	a.rpcRecv!Src(new Connection(), 2 ~ serialize(1f));
	assert(lastMsg == "msg3: remote - 1");
	a.rpcRecv!Src(new Connection(), 3 ~ serialize(1f));
	assert(lastMsg == "msg4: remote - 1");
}
unittest {
	pragma(msg, "Compiling Test C");
	import std.stdio;
	writeln("Running Test C");
	import std.exception;
	import std.conv;
	
	enum SrcClient;
	enum SrcServer;
	class Client {}
	
	string lastMsg = "";
	class A {
		@RPC!SrcClient
		void msg(int x, Client client) {
			lastMsg = "msg: "~x.to!string;
		}
		@RPC!SrcServer
		void msg2(int x) {
			lastMsg = "msg2: "~x.to!string;
		}
		@RPC!SrcClient @RPC!SrcServer
		void msg3(int x) {
			lastMsg = "msg3: "~x.to!string;
		}
		mixin MakeRPCReceive!(SrcClient, Client);
		mixin MakeRPCReceive!(SrcServer);
	}
	A a = new A;
	a.rpcRecv!SrcClient(new Client, 0 ~ serialize(1));
	assert(lastMsg == "msg: 1");
	a.rpcRecv!SrcClient(new Client, 1 ~ serialize(1));
	assert(lastMsg == "msg3: 1");
	a.rpcRecv!SrcServer(0 ~ serialize(1));
	assert(lastMsg == "msg2: 1");
	a.rpcRecv!SrcServer(1 ~ serialize(1));
	assert(lastMsg == "msg3: 1");
}
unittest {
	pragma(msg, "Compiling Test D");
	import std.stdio;
	writeln("Running Test D");
	import std.exception;
	import std.conv;
	
	enum Src;
	
	string lastMsg = "";
	const(ubyte)[] lastSendData = [];
	class A {
		@RPCSend!Src
		void rpcSend(const(ubyte)[] data) {
			lastSendData = data;
		}
		@RPC!Src
		void msg(int x) {
			lastMsg = "msg: "~x.to!string;
		}
		mixin MakeRPCReceive!Src;
		mixin MakeRPCSend!Src;
	}
	A a = new A;
	a.msg_send!Src(5);
	assert(lastSendData == [0,5,0,0,0]);
}
unittest {
	pragma(msg, "Compiling Test E");
	import std.stdio;
	writeln("Running Test E");
	import std.exception;
	import std.conv;
	
	enum SrcClient;
	enum SrcServer;
	class Client {}
	
	string lastMsg = "";
	const(ubyte)[] lastSendData = [];
	class A {
		@RPC!SrcClient
		void msg(int x, Client client) {
			lastMsg = "msg: "~x.to!string;
		}
		@RPC!SrcServer
		void msg2(int x) {
			lastMsg = "msg2: "~x.to!string;
		}
		@RPC!SrcClient @RPC!SrcServer
		void msg3(int x) {
			lastMsg = "msg3: "~x.to!string;
		}
		mixin MakeRPCReceive!(SrcClient, Client);
		mixin MakeRPCReceive!(SrcServer);
		@RPCSend!SrcClient
		void rpcSend(Client[] clients, const(ubyte)[] data) {
			lastSendData = 0~data;
		}
		@RPCSend!SrcServer
		void rpcSend(const(ubyte)[] data) {
			lastSendData = 1~data;
		}
		mixin MakeRPCSend!(SrcClient, Client);
		mixin MakeRPCSend!(SrcServer);
	}
	A a = new A;
	a.msg_send!SrcClient([new Client], 1);
	assert(lastSendData == [0, 0,1,0,0,0]);
	
	a.msg_send!SrcClient(new Client, 5);
	assert(lastSendData == [0, 0,5,0,0,0]);
	a.msg2_send!SrcServer(5);
	assert(lastSendData == [1, 0,5,0,0,0]);
	a.msg3_send!SrcClient(new Client, 5);
	assert(lastSendData == [0, 1,5,0,0,0]);
	a.msg3_send!SrcServer(5);
	assert(lastSendData == [1, 1,5,0,0,0]);
	
	a.rpcRecv!SrcClient(new Client, 0 ~ serialize(1));
	assert(lastMsg == "msg: 1");
	a.rpcRecv!SrcClient(new Client, 1 ~ serialize(1));
	assert(lastMsg == "msg3: 1");
	a.rpcRecv!SrcServer(0 ~ serialize(1));
	assert(lastMsg == "msg2: 1");
	a.rpcRecv!SrcServer(1 ~ serialize(1));
	assert(lastMsg == "msg3: 1");
}

 
