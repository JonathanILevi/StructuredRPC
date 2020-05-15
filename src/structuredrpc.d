module orderedrpc;

import treeserial;

import std.traits;
import std.meta;

import std.algorithm;
import std.range;

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
template RPCParameters(alias f, ConnectionType) {
	alias Params = Parameters!f;
	static if (is(Params[0] == ConnectionType)) {
		alias RPCParameters = Params[1..$];
	}
	else static if (is(Params[$-1] == ConnectionType)) {
		alias RPCParameters = Params[0..$-1];
	}
	else {
		alias RPCParameters = Params;
	}
}
template RPCParameters(alias f) {
	alias RPCParameters = Parameters!f;
}

template RPCParametersExt(alias rpc, alias SrcType, alias RPCSrc, RPCSrc src) {
	static if (!is(typeof(SrcType) == typeof(null)))
		alias RPCParametersExt = RPCParameters!(rpc!(src), SrcType!(src));
	else
		alias RPCParametersExt = RPCParameters!(rpc!(src));
}
template rpcParametersMatch(alias rpc, alias SrcType, alias RPCSrc, RPCSrc srcs) {
	static foreach (i; 0..flags(srcs).length-1) {
		alias Matcher = aliasSeqMatch!(RPCParametersExt!(rpc,SrcType,RPCSrc,flags(srcs)[i]));
		static if (!is(defined) && !Matcher!(RPCParametersExt!(rpc,SrcType,RPCSrc,flags(srcs)[i+1]))) {
			enum rpcParametersMatch = false;
			enum defined;
		}
	}
	static if (!is(defined))
		enum rpcParametersMatch = true;
}

template RPCSendConnections(alias TrgtType, RPCTrgt, RPCTrgt trgts) {
	static if (!is(typeof(TrgtType)==typeof(null))) {
		template ConnectionsImpl(size_t i) {
			static if (i==trgts.flags.length)
				alias ConnectionsImpl = AliasSeq!();
			else static if (!(is(TrgtType!(trgts.flags[i]) == typeof(null)) || is(typeof(TrgtType!(trgts.flags[i])) == typeof(null))))
				alias ConnectionsImpl = AliasSeq!(TrgtType!(trgts.flags[i])[], ConnectionsImpl!(i+1));
			else
				alias ConnectionsImpl = AliasSeq!(ConnectionsImpl!(i+1));
		}
		alias RPCSendConnections = ConnectionsImpl!0;
	}
	else
		alias RPCSendConnections = AliasSeq!();
}

mixin template MakeRPCsImpl(alias RPCSrc, alias RPCTrgt, alias SrcType, alias TrgtType) {
	import std.meta;
	import std.traits;
	import std.algorithm;
	
	static if (is(RPCTrgt)) {
		////static assert(is(typeof(rpcSend)), "`rpcSend` must be defined or `RPCTrgt` (first arg of MakeRPCs) must be `null`.");
		static foreach (i, rpc; getSymbolsByUDA!(typeof(this), RPC)) {
			mixin(q{
				template }~__traits(identifier, rpc)~q{_send(RPCTrgt trgts) if (is(typeof(rpc!(cast(RPCSrc) trgts.flags[0]))) && rpcParametersMatch!(rpc,SrcType, RPCTrgt, trgts)) }~"{"~q{
					void }~__traits(identifier, rpc)~q{_send(RPCSendConnections!(TrgtType,RPCTrgt,trgts) connections, RPCParametersExt!(rpc, SrcType, RPCSrc, cast(RPCSrc) (trgts.flags[0])) args) {
						ubyte[] data = [rpcIDs!(typeof(this))[i]];
						scope(success)
							rpcSend!trgts(data);
						foreach (i, arg; args) {
							static if (__traits(compiles, arg.serialize)) {
								static if (i==args.length-1)
									alias Attributes = NoLength;
								else
									alias Attributes = AliasSeq!();
								data ~= arg.serialize!Attributes;
							}
							else throw new RPCError("Parameter \""~typeof(arg).stringof~"\" of RPC \""~__traits(identifier, rpc)~"\" cannot be serialized.");
						}
					}
				}~"}"~q{
			});
		}
	}
	void rpcRecv(RPCSrc src)(const(ubyte)[] data) {
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
					static if (__traits(compiles, (lvalueOf!(const(ubyte)[])).deserialize!Param)) {
						static if (i==Params.length-1)
							alias Attributes = NoLength;
						else
							alias Attributes = AliasSeq!();
						args[i] = data.deserialize!(Param, Attributes);
					}
					else throw new RPCError("Parameter \""~Param.stringof~"\" of RPC \""~__traits(identifier, rpcTemplate)~"\" cannot be deserialized.  If it is a ConnectionType then you called the wrong rpcRecv (call rpcRecv with a connection).");
				}
			}
		}
	}
	static if (!is(typeof(SrcType) == typeof(null)))
	void rpcRecv(RPCSrc src)(SrcType!src connection, const(ubyte)[] data) {
		enum ids = rpcIDs!(typeof(this));
		ubyte msgID = data.deserialize!ubyte;
		static foreach(id; ids) {
			if (msgID == id) {
				alias rpcTemplate = rpcByID!(typeof(this),id);
				alias rpc = rpcFunction!((Parameters!(rpcTemplate!src) args)=>rpcTemplate!src(args), SrcType!src);
				alias Params = Parameters!rpc[0..$-1];
				Params args;
				scope (success)
					rpc(args, connection);
				foreach (i, Param; Params) {
					static if (__traits(compiles, (lvalueOf!(const(ubyte)[])).deserialize!Param)) {
						static if (i==Params.length-1)
							alias Attributes = NoLength;
						else
							alias Attributes = AliasSeq!();
						args[i] = data.deserialize!(Param, Attributes);
					}
					else throw new RPCError("Parameter `"~Param.stringof~"` of RPC `"~__traits(identifier, rpcTemplate)~"` cannot be deserialized.  If you think this should be the connection type, then for `"~RPCSrc.stringof~"."~__traits(identifier, src)~"` it should be of type `"~SrcType!src.stringof~"` (Correct parameter or `SrcType` or src).");
				}
			}
		}
	}
}

template MakeRPCsArgs(This, Ts...) {
	static foreach (T; Ts) {
		static if (is(T==enum)) {
			static if (!is(MakeRPCs_RPCSrc)) {
				alias MakeRPCs_RPCSrc = T;
			}
			else static if (!is(MakeRPCs_RPCTrgt)) {
				alias MakeRPCs_RPCTrgt = T;
				static assert(is(typeof(This.rpcSend)), "`MakeRPCs` was given a second enum for `RPCTrgt`, but `rpcSend` is undefined.");
				////static assert(is(typeof(rpcSend!(rvalueOf!RPCTrgt))), "`rpcSend` is undefined, but not right, rpcSend must be: `void rpcSend(RPCTrgt trgts)(...)`");
			}
			else static assert(false, "`MakeRPCs` was given more than 2 enums.  Accepts 0-2.");
		}
		else {
			static if (!is(MakeRPCs_SrcType)) {
				alias MakeRPCs_SrcType = T;
			}
			else static if (!is(MakeRPCs_TrgtType)) {
				alias MakeRPCs_TrgtType = T;
			}
			else static assert(false);
		}
	}
	static if (!is(MakeRPCs_RPCSrc)) {
		alias MakeRPCs_RPCSrc = RPCSrc;
	}
	static if (!is(MakeRPCs_RPCTrgt)) {
		static if (is(typeof(This.rpcSend)))
			alias MakeRPCs_RPCTrgt = RPCSrc;
		else
			enum MakeRPCs_RPCTrgt = null; 
		////static assert(is(typeof(rpcSend!(rvalueOf!RPCTrgt))), "`rpcSend` is undefined, but not right, rpcSend must be: `void rpcSend(RPCTrgt trgts)(...)`.  Either give an appropriate RPCTrgt (pass a second enum to `MakeRPCs`) or `rpcSend` should work with `RPCSrc`.");
	}
	static if (!(is(MakeRPCs_SrcType) || is(typeof(MakeRPCs_SrcType)))) {
		enum MakeRPCs_SrcType = null;
	}
	static if (!(is(MakeRPCs_TrgtType) || is(typeof(MakeRPCs_TrgtType)))) {
		static if (is(typeof(MakeRPCs_SrcType) == typeof(null)) || is(typeof(MakeRPCs_RPCTrgt) == typeof(null)))
			enum MakeRPCs_TrgtType = null;
		else {
			template MakeRPCs_TrgtType(MakeRPCs_RPCTrgt trgt) {
				alias MakeRPCs_TrgtType = MakeRPCs_SrcType!(cast(MakeRPCs_RPCSrc) trgt);
			}
		}
	}
	
	static if (!is(MakeRPCs_RPCSrc))
		static assert(![EnumMembers!MakeRPCs_RPCSrc].any!((MakeRPCs_RPCSrc a)=>a==0), "`RPCTrgt` must be a flag type.");
	static if (is(MakeRPCs_RPCTrgt))
		static assert(![EnumMembers!MakeRPCs_RPCTrgt].any!((MakeRPCs_RPCTrgt a)=>a==0), "`RPCTrgt` must be a flag type.");
	
	alias MakeRPCsArgs = AliasSeq!(MakeRPCs_RPCSrc, MakeRPCs_RPCTrgt, MakeRPCs_SrcType, MakeRPCs_TrgtType);
}

template MakeRPCs(Ts...) {
	mixin MakeRPCsImpl!(MakeRPCsArgs!(typeof(this),Ts));
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
		mixin MakeRPCs!(RPCSrc,ConnectionType);
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
unittest {
	pragma(msg, "Compiling Test C");
	import std.stdio;
	writeln("Running Test C");
	import std.exception;
	import std.conv;
	
	string lastMsg = "";
	ubyte[] lastSendData = [];
	class A {
		void rpcSend(RPCSrc src)(ubyte[] data) {
			lastSendData = data;
		}
		@RPC
		void msg(RPCSrc src=RPCSrc.self)(int x) {
			lastMsg = "msg: "~src.to!string~" - "~x.to!string;
		}
		mixin MakeRPCs;
	}
	A a = new A;
	a.msg_send!(RPCSrc.remote)(5);
	assert(lastSendData == [0,5,0,0,0]);
}
unittest {
	pragma(msg, "Compiling Test D");
	import std.stdio;
	writeln("Running Test D");
	import std.exception;
	import std.conv;
	
	string lastMsg = "";
	ubyte[] lastSendData = [];
	class A {
		void rpcSend(RPCSrc src)(ubyte[] data) {
			lastSendData = data;
		}
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
	a.msg_send!(RPCSrc.remote)(5);
	assert(lastSendData == [0,5,0,0,0]);
	a.msg2_send!(RPCSrc.remote)(1.5);
	assert(lastSendData == (cast(ubyte)1) ~ 1.5f.serialize);
}
unittest {
	pragma(msg, "Compiling Test E");
	import std.stdio;
	writeln("Running Test E");
	import std.exception;
	import std.conv;
	
	string lastMsg = "";
	ubyte[] lastSendData = [];
	class Connection {}
	template ConnectionType(RPCSrc src) {
		static if (src == RPCSrc.self)
			alias ConnectionType = typeof(null);
		else static if (src == RPCSrc.remote)
			alias ConnectionType = Connection;
		else static assert(false, "Missing case.");
	}
	class A {
		void rpcSend(RPCSrc trgts)(ubyte[] data) {
			lastSendData = data;
		}
		@RPC
		template msg(RPCSrc src=RPCSrc.self) {
			static if (src == RPCSrc.self)
			void msg (int x) {
				lastMsg = "msg2: "~src.to!string~" - "~x.to!string;
			}
			static if (src == RPCSrc.remote)
			void msg (int x, Connection con) {
				lastMsg = "msg2: "~src.to!string~" - "~x.to!string;
			}
		}
		@RPC
		template msg2(RPCSrc src=RPCSrc.self) {
			static if (src == RPCSrc.self)
			void msg2 (float x) {
				lastMsg = "msg2: "~src.to!string~" - "~x.to!string;
			}
			static if (src == RPCSrc.remote)
			void msg2 (float x, long y) {
				lastMsg = "msg2: "~src.to!string~" - "~x.to!string~" - "~y.to!string;
			}
		}
		mixin MakeRPCs!(RPCSrc,RPCSrc,ConnectionType);
	}
	A a = new A;
	a.msg_send!(RPCSrc.self)(5);
	assert(lastSendData == [0,5,0,0,0]);
	a.msg_send!(RPCSrc.remote)([new Connection], 5);
	assert(lastSendData == [0,5,0,0,0]);
	a.msg_send!(RPCSrc.self|RPCSrc.remote)([new Connection], 5);
	assert(lastSendData == [0,5,0,0,0]);
	a.msg2_send!(RPCSrc.self)(1.5);
	assert(lastSendData == (cast(ubyte)1) ~ 1.5f.serialize);
	a.msg2_send!(RPCSrc.remote)([new Connection], 1.5, 2);
	assert(lastSendData == (cast(ubyte)1) ~ 1.5f.serialize ~ 2L.serialize);
	assert(!__traits(compiles, a.msg2_send!(RPCSrc.self | RPCSrc.remote)(1.5)));
	assert(!__traits(compiles, a.msg2_send!(RPCSrc.self | RPCSrc.remote)(1.5, 2)));
}
unittest {
	pragma(msg, "Compiling Test F");
	import std.stdio;
	writeln("Running Test F");
	import std.exception;
	import std.conv;
	
	enum Src {
		server = 0x1,
		client = 0x2,
	}
	enum Trgt {
		client = 0x1,
		server = 0x2,
	}
	
	ubyte[] lastSendData = [];
	string lastMsg = "";
	class A {
		void rpcSend(Trgt trgts)(ubyte[] data) {
			lastSendData = data;
		}
		@RPC
		void msg(Src src:Src.client)(int x) {
			lastMsg = "msg: "~src.to!string~" - "~x.to!string;
		}
		@RPC
		void msg2(Src src:Src.server)(long x) {
			lastMsg = "msg2: "~src.to!string~" - "~x.to!string;
		}
		mixin MakeRPCs!(Src, Trgt);
	}
	A a = new A;
	a.msg_send!(Trgt.server)(5);
	assert(lastSendData == [0, 5,0,0,0]);
	a.msg2_send!(Trgt.client)(5);
	assert(lastSendData == [1, 5,0,0,0, 0,0,0,0]);
	assert(!__traits(compiles, a.msg_send!(Trgt.client)(5)));
	assert(!__traits(compiles, a.msg2_send!(Trgt.server)(5)));
}
unittest {
	pragma(msg, "Compiling Test G");
	import std.stdio;
	writeln("Running Test G");
	import std.exception;
	import std.conv;
	
	string lastMsg = "";
	ubyte[] lastSendData = [];
	class RemoteConnection {}
	class SelfConnection {}
	template ConnectionType(RPCSrc src) {
		static if (src == RPCSrc.self)
			alias ConnectionType = SelfConnection;
		else static if (src == RPCSrc.remote)
			alias ConnectionType = RemoteConnection;
		else static assert(false, "Missing case.");
	}
	class A {
		void rpcSend(RPCSrc trgts)(ubyte[] data) {
			lastSendData = data;
		}
		@RPC
		template msg(RPCSrc src=RPCSrc.self) {
			static if (src == RPCSrc.self)
			void msg (int x) {
				lastMsg = "msg2: "~src.to!string~" - "~x.to!string;
			}
			static if (src == RPCSrc.remote)
			void msg (int x, RemoteConnection con) {
				lastMsg = "msg2: "~src.to!string~" - "~x.to!string;
			}
		}
		mixin MakeRPCs!(RPCSrc,RPCSrc,ConnectionType);
	}
	A a = new A;
	a.msg_send!(RPCSrc.self)([new SelfConnection], 5);
	assert(lastSendData == [0,5,0,0,0]);
	a.msg_send!(RPCSrc.remote)([new RemoteConnection], 5);
	assert(lastSendData == [0,5,0,0,0]);
	a.msg_send!(RPCSrc.self|RPCSrc.remote)([new SelfConnection], [new RemoteConnection], 5);
	assert(lastSendData == [0,5,0,0,0]);
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
template aliasSeqMatch(As...) {
	template aliasSeqMatch(Bs...) {
		enum aliasSeqMatch = is(As==Bs);
	}
}
template parametersMatch(alias f, alias b) {
	enum parametersMatch = is(Parameters!f == Parameters!b);
}
unittest {
	void a(int, float);
	void b(int, float);
	void c(int, long);
	assert(parametersMatch!(a,b));
	assert(!parametersMatch!(a,c));
	assert(parametersMatch!(b,a));
	assert(!parametersMatch!(c,b));
}
template allParametersMatch(Ts...) {
	static foreach (i; 0..Ts.length-1) {
		static if (!is(defined) && !parametersMatch!(Ts[i],Ts[i+1])) {
			enum allParametersMatch = false;
			enum defined;
		}
	}
	static if (!is(defined))
		enum allParametersMatch = true;
}
unittest {
	void a(int, float);
	void b(int, float);
	void c(int, float);
	void d(int, long);
	assert(allParametersMatch!(a,b,c));
	assert(!allParametersMatch!(a,b,d));
	assert(allParametersMatch!(c,b,a));
	assert(!allParametersMatch!(a,d,c));
}
////template flags(alias fs) if (is(typeof(fs)==enum)) {
////	enum flags = Filter!(staticLift!(f=>f & fs), EnumMembers!(typeof(fs)));
////}
////template flags(F, F fs) if (is(F==enum)) {
////	enum flags = Filter!(staticLift!(f=>f & fs), EnumMembers!(typeof(fs)));
////}
F[] flags(F)(F fs) {
	return filter!(f=>f & fs)([EnumMembers!(F)]).array;
}
unittest {
	enum E {
		a = 0x1,
		b = 0x2,
		c = 0x4,
	}
	assert(flags(E.a|E.c) == [E.a,E.c]);
}

template Exclam(alias t, Ts...) {
	alias Exclam = t!Ts;
}
template AliasSeqOf(alias R) if (isInputRange!(typeof(R))) {
    import std.typetuple : TT = TypeTuple;
    static if (R.empty)
        alias AliasSeqOf = TT!();
        else
        alias AliasSeqOf = TT!(R.front(), AliasSeqOf!(R.dropOne()));
}

 
