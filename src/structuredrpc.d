module orderedrpc;

import treeserial;

import std.traits;
import std.meta;

enum RPCSrc {
	self	= 0x1,
	remote	= 0x2,
}

struct RPC {
	ubyte id;
}

class RPCError : Exception {
	this(string msg, string file = __FILE__, size_t line = __LINE__) {
		super(msg, file, line);
	}
}

template rpcsWithID(alias symbol) {
	template Match(short id_, alias mem_) {
		enum id = id_;
		alias mem = mem_;
	}
	template f(alias last, alias mem) {
		alias udas = getUDAs!(mem, RPC);
		static assert(udas.length == 1);
		static if (is(udas[$-1])) {
			alias f = Match!(last.id+1, mem);
		}
		else {
			alias f = Match!(udas[$-1].id, mem);
		}
	}
	alias rpcsWithID = staticScan!(f, Match!(-1, null), getSymbolsByUDA!(symbol, RPC));
}

enum rpcIDs(alias symbol)() {
	ubyte next = 0;
	ubyte[] ids = [];
	foreach (mem; getSymbolsByUDA!(symbol, RPC)) {
		alias udas = getUDAs!(mem, RPC);
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
template rpcByID(alias symbol, ubyte id) {
	import std.algorithm;
	alias rpcByID = getSymbolsByUDA!(symbol, RPC)[rpcIDs!symbol.countUntil(id)];
}

template RPCMsgData(alias f) {
	////static if (Parameters!(rpc!src).length == 1) {
	////	static assert(__traits(compiles, rpc!src(data[1..$].deserialize!(Parameters!(rpc!src)[0]))), "RPC function must take either 1 serializable argument or 2 arguments, a `Connection` and another serializable one (either order).");
	////	rpc!src(data[1..$].deserialize!(Parameters!(rpc!src)[0]));
	////}
	////else static if (Parameters!(rpc!src).length == 2) {
	////	static if (__traits(compiles, rpc!src(connection, data[1..$].deserialize!(Parameters!(rpc!src)[1]))))
	////		rpc!src(connection, data[1..$].deserialize!(Parameters!(rpc!src)[1]));
	////	else static if (__traits(compiles, rpc!src(data[1..$].deserialize!(Parameters!(rpc!src)[0]),connection)))
	////		rpc!src(data[1..$].deserialize!(Parameters!(rpc!src)[0]), connection);
	////	else static assert(false, "RPC function must take either 1 serializable argument or 2 arguments, a `Connection` and another serializable one (either order).");
	////}
}


template rpcFunction(alias f, ConnectionType) {
	alias Params = Parameters!f;
	static if (is(Params[0] == ConnectionType)) {
		pragma(inline, true)
		void rpcFunction(Params[1..$] args, ConnectionType connection) {
			f(connection, args);
		}
	}
	else static if (is(Params[$-1] == ConnectionType)) {
		pragma(inline, true)
		void rpcFunction(Params[0..$-1] args, ConnectionType connection) {
			f(args, connection);
		}
	}
	else {
		pragma(inline, true)
		void rpcFunction(Params args, ConnectionType connection) {
			f(args);
		}
	}
}
template rpcFunction(alias f) {
	alias Params = Parameters!f;
	pragma(inline, true)
	void rpcFunction(Params args) {
		f(args);
	}
}

mixin template MakeRPCs(alias GetConnectionType=null, alias RPCSrc=RPCSrc) {
	////static if (is(typeof(rpcSend))) {
	////	static foreach (rpc; getSymbolsByUDA!(typeof(this), RPC)) {
	////		void send(string type, RPCSrc srcs)(Parameters!(Filter!(staticLift!(m=>m & srcs), EnumMembers!RPCSrc)[0])) if (staticFold!(parametersMatch, staticMap!(rpc, Filter!(staticLift!(m=>m & srcs), EnumMembers!RPCSrc)))) {
	////			writeln;
	////		}
	////		mixin("void "~__traits(identifier, rpc)~"_send(RPCSrc srcs)(Parameters!(Filter!(staticLift!(m=>m & srcs), EnumMembers!RPCSrc)[0])) if (staticFold!(parametersMatch, staticMap!(rpc, Filter!(staticLift!(m=>m & srcs), EnumMembers!RPCSrc)))) {
	////		}");
	////	}
	////}
	////static foreach (name; Filter!(isNotThis, __traits(derivedMembers, typeof(this)))) {
	////	enum string fieldCode = `Alias!(__traits(getMember, typeof(this), "` ~ name ~ `"))`;
	////	mixin("alias field = " ~ fieldCode ~ ";");
	////	pragma(msg, TemplateArgsOf!(field));
	////	pragma(msg, __traitsParameters!field);
	////	static if (__traits(compiles, hasUDA!(field, RPC))) {
	////		pragma(msg, "hasUDA");
	////	}
	////}
	void rpcRecv(RPCSrc src)(ubyte[] data) {
		////pragma(msg, rpcsWithID!(typeof(this)));
		enum ids = rpcIDs!(typeof(this));
		ubyte msgID = data.deserialize!ubyte;
		static foreach(id; ids) {
			if (msgID == id) {
				alias rpcTemplate = rpcByID!(typeof(this),id);
				alias rpc = rpcFunction!((Parameters!(rpcTemplate!src) args)=>rpcTemplate!src(args));
				alias Params = Parameters!rpc;
				Params args;
				scope (success)
					rpc(args);
				foreach (i, Param; Params) {
					static if (__traits(compiles, (lvalueOf!(ubyte[])).deserialize!Param)) {
						static if (i==Params.length-1)
							alias Attributes = NoLength;
						else
							alias Attributes = AliasSeq!();
						args[i] = data.deserialize!(Param, Attributes);
					}
					else throw new RPCError("Parameter \""~Param.stringof~"\" of RPC \""~__traits(identifier, rpcTemplate)~"\" cannot be deserialized.  If it is a ConnectionType then you called the wrong rpcRecv (call rpcRecv with a connection).");
				}
				////static assert(__traits(compiles, rpc!src), "RPC funciton must be a tempate with RPCSrc (`void fun(RPCSrc src)(arg)`).");
				////////static assert(Parameters!(rpc!src).length == 1 && __traits(compiles, rpc!src(data[1..$].deserialize!(Parameters!(rpc!src)[0]))), "no connection was passed to rpcRecv so: RPC function must take 1 serializable argument; if a connection was passed: RPC function can also take 2 arguments, a `Connection` and another serializable one (either order).");
				////pragma(msg, Parameters!(rpc!src).length);
				////pragma(msg, __traits(compiles, rpc!src(data[1..$].deserialize!(Parameters!(rpc!src)[0]))));
				////static if (Parameters!(rpc!src).length == 1 && __traits(compiles, rpc!src(data[1..$].deserialize!(Parameters!(rpc!src)[0]))))
				////	rpc!src(data[1..$].deserialize!(Parameters!(rpc!src)[0]));
				////else assert(false, "No connection was passed to rpcRecv so: RPC function must take 1 serializable argument; if a connection was passed: RPC function can also take 2 arguments, a `Connection` and another serializable one (either order).");
			}
		}
	}
	static if (!is(typeof(GetConnectionType) == typeof(null)))
	void rpcRecv(RPCSrc src)(GetConnectionType!src connection, ubyte[] data) {
		////pragma(msg, rpcsWithID!(typeof(this)));
		enum ids = rpcIDs!(typeof(this));
		ubyte msgID = data.deserialize!ubyte;
		static foreach(id; ids) {
			if (msgID == id) {
				alias rpcTemplate = rpcByID!(typeof(this),id);
				alias rpc = rpcFunction!((Parameters!(rpcTemplate!src) args)=>rpcTemplate!src(args), GetConnectionType!src);
				alias Params = Parameters!rpc[0..$-1];
				Params args;
				scope (success)
					rpc(args, connection);
				foreach (i, Param; Params) {
					static if (__traits(compiles, (lvalueOf!(ubyte[])).deserialize!Param)) {
						static if (i==Params.length-1)
							alias Attributes = NoLength;
						else
							alias Attributes = AliasSeq!();
						args[i] = data.deserialize!(Param, Attributes);
					}
					else throw new RPCError("Parameter `"~Param.stringof~"` of RPC `"~__traits(identifier, rpcTemplate)~"` cannot be deserialized.  If you think this should be the connection type, then for `"~RPCSrc.stringof~"."~__traits(identifier, src)~"` it should be of type `"~GetConnectionType!src.stringof~"` (Correct parameter or `GetConnectionType` or src).");
				}
				///ralias rpc = rpcByID!(typeof(this),id);
				///rstatic assert(__traits(compiles, rpc!src), "RPC funciton must be a tempate with RPCSrc (`void fun(RPCSrc src)(arg)`).");
				////static if (Parameters!(rpc!src).length == 1) {
				////	static assert(__traits(compiles, rpc!src(data[1..$].deserialize!(Parameters!(rpc!src)[0]))), "RPC function must take either 1 serializable argument or 2 arguments, a `Connection` and another serializable one (either order).");
				////	rpc!src(data[1..$].deserialize!(Parameters!(rpc!src)[0]));
				////}
				////else static if (Parameters!(rpc!src).length == 2) {
				////	static if (__traits(compiles, rpc!src(connection, data[1..$].deserialize!(Parameters!(rpc!src)[1]))))
				////		rpc!src(connection, data[1..$].deserialize!(Parameters!(rpc!src)[1]));
				////	else static if (__traits(compiles, rpc!src(data[1..$].deserialize!(Parameters!(rpc!src)[0]),connection)))
				////		rpc!src(data[1..$].deserialize!(Parameters!(rpc!src)[0]), connection);
				////	else static assert(false, "RPC function must take either 1 serializable argument or 2 arguments, a `Connection` and another serializable one (either order).");
				////}
				////else static assert(false, "RPC function must take either 1 serializable argument or 2 arguments, a `Connection` and another serializable one (either order).");
			}
		}
	}
}

unittest {
	pragma(msg, "Compiling Test A");
	import std.stdio;
	writeln("Running Test A");
	import std.exception;
	import std.conv;
	
	string lastMsg = "";
	class A {
		@RPC
		void msg(RPCSrc src=RPCSrc.self)(int x) {
			lastMsg = "msg: "~src.to!string~" - "~x.to!string;
		}
		@RPC
		void msg2(RPCSrc src=RPCSrc.self)(float x) {
			lastMsg = "msg2: "~src.to!string~" - "~x.to!string;
		}
		mixin MakeRPCs;
	}
	A a = new A;
	a.msg!(RPCSrc.self)(5);
	assert(lastMsg == "msg: self - 5");
	a.msg!(RPCSrc.remote)(5);
	assert(lastMsg == "msg: remote - 5");
	a.msg(5);
	assert(lastMsg == "msg: self - 5");
	a.rpcRecv!(RPCSrc.remote)(0 ~ serialize(1));
	assert(lastMsg == "msg: remote - 1");
	a.rpcRecv!(RPCSrc.remote)(1 ~ serialize(1.5f));
	assert(lastMsg == "msg2: remote - 1.5");
}
unittest {
	pragma(msg, "Compiling Test B");
	import std.stdio;
	writeln("Running Test B");
	import std.exception;
	import std.conv;
	
	string lastMsg = "";
	class Connection {}
	template ConnectionType(RPCSrc src) {
		static if (src == RPCSrc.self)
			alias ConnectionType = typeof(null);
		else static if (src == RPCSrc.remote)
			alias ConnectionType = Connection;
		else static assert(false, "Missing case.");
	}
	class A {
		@RPC
		void msg(RPCSrc src=RPCSrc.self)(int x) {
			lastMsg = "msg: "~src.to!string~" - "~x.to!string;
		}
		@RPC
		template msg2(RPCSrc src=RPCSrc.self) {
			static if (src == RPCSrc.self)
			void msg2 (float x) {
				lastMsg = "msg2: "~src.to!string~" - "~x.to!string;
			}
			static if (src == RPCSrc.remote)
			void msg2 (float x, Connection con) {
				lastMsg = "msg2: "~src.to!string~" - "~x.to!string;
			}
		}
		mixin MakeRPCs!ConnectionType;
	}
	A a = new A;
	a.msg!(RPCSrc.self)(5);
	assert(lastMsg == "msg: self - 5");
	a.msg!(RPCSrc.remote)(5);
	assert(lastMsg == "msg: remote - 5");
	a.msg(5);
	assert(lastMsg == "msg: self - 5");
	a.rpcRecv!(RPCSrc.remote)(0 ~ serialize(1));
	assert(lastMsg == "msg: remote - 1");
	assertThrown!Throwable(a.rpcRecv!(RPCSrc.remote)(1 ~ serialize(1.5f)));
	a.rpcRecv!(RPCSrc.remote)(new Connection(), 0 ~ serialize(1));
	assert(lastMsg == "msg: remote - 1");
	a.rpcRecv!(RPCSrc.remote)(new Connection(), 1 ~ serialize(1.5f));
	assert(lastMsg == "msg2: remote - 1.5");
	a.rpcRecv!(RPCSrc.self)(null, 0 ~ serialize(1));
	assert(lastMsg == "msg: self - 1");
	a.rpcRecv!(RPCSrc.self)(null, 1 ~ serialize(1.5f));
	assert(lastMsg == "msg2: self - 1.5");
}

template staticScan(alias f, List...)
if (List.length > 1)
{
	static if (List.length == 2)
	{
		alias staticScan = f!(List[0], List[1]);
	}
	else
	{
		alias staticScan = AliasSeq!(f!(List[0], List[1]), staticScan!(f, f!(List[0], List[1]), List[2..$]));
	}
}
template staticFold(alias f, List...)
if (List.length > 1)
{
	static if (List.length == 2)
	{
		alias staticFold = f!(List[0], List[1]);
	}
	else
	{
		alias staticFold = staticFold!(f, f!(List[0], List[1]), List[2..$]);
	}
}
template staticLift(alias f) {
	template staticLift(ts...) {
		enum staticLift = f(ts);
	}
}
template parametersMatch(alias f, alias b) {
	enum parametersMatch = Parameters!f == Parameters!b;
}


 
