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


template RPCParameters(alias rpc, Src, Connection) {
	static if (__traits(isTemplate, rpc)) {
		alias Params = Parameters!(rpc!Src);
	}
	else {
		alias Params = Parameters!rpc;
	}
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

string identifier(string id) {
	import std.conv;
	return id.strip('_');
	////return id.find!"a != '_'".array.to!string;
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
					alias rpcTemplate = rpcByID!(Src, typeof(this),id);
					static if (__traits(isTemplate, rpcTemplate))
						alias rpc = rpcTemplate!Src;
					else
						alias rpc = rpcTemplate;
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
					alias rpcTemplate = rpcByID!(Src, typeof(this),id);
					static if (__traits(isTemplate, rpcTemplate))
						alias rpc = rpcTemplate!Src;
					else
						alias rpc = rpcTemplate;
					alias Params = RPCParameters!(rpc, Src, Connection);
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
	import treeserial;
	mixin MakeRPCReceive!(Src, typeof(null), Serializer!());
}
mixin template MakeRPCReceive(Src, alias Serializer) {
	mixin MakeRPCReceive!(Src, typeof(null), Serializer);
}
mixin template MakeRPCReceive(Src, Connection) {
	import treeserial;
	mixin MakeRPCReceive!(Src, Connection, Serializer!());
}


mixin template MakeRPCSendToImpl(SendTo, Src, ToConnection, Connection, alias Serializer) {
	import std.meta;
	import std.traits;
	import std.algorithm;
	import treeserial;
	
	static foreach (i, rpc; getSymbolsByUDA!(SendTo, RPC!Src)) {
		mixin(q{
			template }~__traits(identifier, rpc).identifier~q{_send(S:Src) }~"{"~q{
				auto }~__traits(identifier, rpc).identifier~q{_send(RPCConnectionsParam!Connection connections, const RPCParameters!(rpc, Src, ToConnection) args) {
					const(ubyte)[] data = Serializer.serialize!ubyte(rpcIDs!(Src, SendTo)[i]);
					alias rpcSend = getSymbolsByUDA!(typeof(this), RPCSend!Src)[0];
					foreach (i, arg; args) {
						static if (serializable!arg) {
							static if (i==args.length-1)
								alias Attributes = NoLength;
							else
								alias Attributes = AliasSeq!();
							data ~= Serializer.Subserializer!Attributes.serialize(arg);
						}
						else throw new RPCError("Parameter \""~typeof(arg).stringof~"\" of RPC \""~__traits(identifier, rpc)~"\" cannot be serialized.");
					}
					return rpcSend(connections, data);
				}
				
				// So last last argument can be different for each client.
				static if (RPCParameters!(rpc, Src, ToConnection).length >= 1)
				auto }~__traits(identifier, rpc).identifier~q{_send(RPCConnectionsParam!Connection connections, const RPCParameters!(rpc, Src, ToConnection)[0..$-1] args, const RPCParameters!(rpc, Src, ToConnection)[$-1][] lastArgs) {
					assert(connections.length == lastArgs.length);
					ubyte[] data = Serializer.serialize!ubyte(rpcIDs!(Src, SendTo)[i]);
					alias rpcSend = getSymbolsByUDA!(typeof(this), RPCSend!Src)[0];
					foreach (i, arg; args) {
						static if (serializable!arg) {
							data ~= Serializer.Subserializer!().serialize(arg);
						}
						else throw new RPCError("Parameter \""~typeof(arg).stringof~"\" of RPC \""~__traits(identifier, rpc)~"\" cannot be serialized.");
					}
					foreach (i, connection; connections) {
						data.assumeSafeAppend;
						rpcSend([connection], data~Serializer.Subserializer!NoLength.serialize(lastArgs[i]));
					}
				}
				
				static if (!is(Connection == typeof(null)))
				auto }~__traits(identifier, rpc).identifier~q{_send(Connection connection, const RPCParameters!(rpc, Src, Connection) args) }~"{
					return "~__traits(identifier, rpc).identifier~"_send([connection], args);
				}
			}"~q{
		});
	}
}
mixin template MakeRPCSendTo(SendTo, Src, ConnectionTo, alias Serializer) {
	import std.traits;
	static if (Parameters!(getSymbolsByUDA!(typeof(this), RPCSend!Src)[0]).length==1)
		mixin MakeRPCSendToImpl!(SendTo, Src, ConnectionTo, typeof(null), Serializer);
	else
		mixin MakeRPCSendToImpl!(SendTo, Src, ConnectionTo, ForeachType!(Parameters!(getSymbolsByUDA!(typeof(this), RPCSend!Src)[0])[0]), Serializer);
}
mixin template MakeRPCSendTo(SendTo, Src) {
	import treeserial;
	mixin MakeRPCSendTo!(SendTo, Src, typeof(null), Serializer!());
}
mixin template MakeRPCSendTo(SendTo, Src, alias Serializer) {
	mixin MakeRPCSendTo!(SendTo, Src, typeof(null), Serializer);
}
mixin template MakeRPCSendTo(SendTo, Src, Connection) {
	import treeserial;
	mixin MakeRPCSendTo!(SendTo, Src, Connection, Serializer!());
}

mixin template MakeRPCSend(Src, Connection, alias Serializer) {
	mixin MakeRPCSendTo!(typeof(this), Src, Connection, Serializer);
}
mixin template MakeRPCSend(Src) {
	import treeserial;
	mixin MakeRPCSendTo!(typeof(this), Src, typeof(null), Serializer!());
}
mixin template MakeRPCSend(Src, alias Serializer) {
	mixin MakeRPCSendTo!(typeof(this), Src, typeof(null), Serializer);
}
mixin template MakeRPCSend(Src, Connection) {
	import treeserial;
	mixin MakeRPCSendTo!(typeof(this), Src, Connection, Serializer!());
}

 
