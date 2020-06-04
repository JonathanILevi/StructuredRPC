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
struct RPCCon(T) {
	alias Connection = T;
}

class RPCError : Exception {
	this(string msg, string file = __FILE__, size_t line = __LINE__) {
		super(msg, file, line);
	}
}


template ConnectionType(alias src) {
	static if (hasUDA!(src,RPCCon))
		alias ConnectionType = getUDAs!(src,RPCCon)[$-1].Connection;
	else
		alias ConnectionType = typeof(null);
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
template RPCParameters(alias f, ConType) {
	alias Params = Parameters!f;
	static if (is(ConType == typeof(null))) {
		alias RPCParameters = Params;
	}
	else static if (is(Params[0] == ConType)) {
		alias RPCParameters = Params[1..$];
	}
	else static if (is(Params[$-1] == ConType)) {
		alias RPCParameters = Params[0..$-1];
	}
	else {
		alias RPCParameters = Params;
	}
}
template RPCParameters(alias f) {
	alias RPCParameters = Parameters!f;
}

template RPCParametersExt(alias rpc, alias RPCSrc, RPCSrc src) {
	alias RPCParametersExt = RPCParameters!(rpc!src, ConnectionType!src);
}
template rpcParametersMatch(alias rpc, alias RPCSrc, RPCSrc srcs) {
	static foreach (i; 0..flags(srcs).length-1) {
		alias Matcher = aliasSeqMatch!(RPCParametersExt!(rpc,RPCSrc,flags(srcs)[i]));
		static if (!is(defined) && !Matcher!(RPCParametersExt!(rpc,RPCSrc,flags(srcs)[i+1]))) {
			enum rpcParametersMatch = false;
			enum defined;
		}
	}
	static if (!is(defined))
		enum rpcParametersMatch = true;
}

////template RPCSendConnections(RPCTrgt, RPCTrgt trgts) {
////	template ConnectionsImpl(size_t i) {
////		static if (i==trgts.flags.length)
////			alias ConnectionsImpl = AliasSeq!();
////		else {
////			static if (!(is(ConnectionType!(trgts.flags[i]) == typeof(null)) || is(typeof(ConnectionType!(trgts.flags[i])) == typeof(null))))
////				alias ConnectionsImpl = AliasSeq!(ConnectionType!(trgts.flags[i])[], ConnectionsImpl!(i+1));
////			else
////				alias ConnectionsImpl = AliasSeq!(ConnectionsImpl!(i+1));
////		}
////	}
////	alias RPCSendConnections = ConnectionsImpl!0;
////}

template RPCSendConnections(alias trgts) {
	alias RPCSendConnections = staticMap!(AliasLambda!"T[]", staticMap!(ConnectionParam, ArrayExpand!(trgts.flags)));
}
template rpcSendConnection(alias trgts, size_t i, connections...) {
	static if (hasConnection!(trgts.flags[i]))
		alias rpcSendConnection = connections[(cast(bool[])[staticMap!(hasConnection, ArrayExpand!(trgts.flags[0..i]))]).filter!(_=>_).walkLength];
	else
		alias rpcSendConnection = AliasSeq!();
}

template ConnectionParam(alias src_) {
	// This is a hack to solve some qerks enum member UDAs.
	alias Src = typeof(src_);
	enum src = EnumMembers!Src[[EnumMembers!Src].countUntil(src_)];
	
	static if (hasUDA!(src,RPCCon))
		alias ConnectionParam = getUDAs!(src,RPCCon)[$-1].Connection;
	else
		alias ConnectionParam = AliasSeq!();
}
template hasConnection(alias src_) {
	// This is a hack to solve some qerks enum member UDAs.
	alias Src = typeof(src_);
	enum src = EnumMembers!Src[[EnumMembers!Src].countUntil(src_)];
	
	enum hasConnection = hasUDA!(src,RPCCon);
}

template MakeRPCsImpl(alias RPCSrc, alias RPCTrgt, alias Serializer) {
	import std.meta;
	import std.traits;
	import std.algorithm;
	import treeserial;
	
	static if (is(RPCTrgt)) {
		static foreach (i, rpc; getSymbolsByUDA!(typeof(this), RPC)) {
			mixin(q{
				template }~__traits(identifier, rpc)~q{_send(RPCTrgt trgts) }~"{"~q{
					alias _ =  Parameters!(rpc!(cast(RPCSrc) trgts.flags[0]));// Stops some glitchy "recursive template expansion" compile error.
					static assert(trgts.flags.length>0 && rpcParametersMatch!(rpc, RPCSrc, cast(RPCSrc) trgts));
					void }~__traits(identifier, rpc)~q{_send(RPCSendConnections!trgts connections, RPCParametersExt!(rpc, RPCSrc, cast(RPCSrc) (trgts.flags[0])) args) {
						const(ubyte)[] data = Serializer.serialize!ubyte(rpcIDs!(typeof(this))[i]);
						scope(success) {
							static if (__traits(compiles, rpcSend!trgts))
								rpcSend!trgts(connections, data);
							else
								static foreach(i, trgt; trgts.flags) {
									rpcSend!trgt(rpcSendConnection!(trgts,i,connections), data);
								}
						}
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
				}~"}"~q{
			});
		}
	}
	void rpcRecv(RPCSrc src)(const(ubyte)[] data) {
		enum ids = rpcIDs!(typeof(this));
		ubyte msgID = Serializer.deserialize!ubyte(data);
		static foreach(id; ids) {
			if (msgID == id) {
				alias rpcTemplate = rpcByID!(typeof(this),id);
				static if (is(typeof(rpcTemplate!src))) {
					alias rpc = rpcFunction!((Parameters!(rpcTemplate!src) args)=>rpcTemplate!src(args));
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
						else throw new RPCError("Parameter \""~Param.stringof~"\" of RPC \""~__traits(identifier, rpcTemplate)~"\" cannot be deserialized.  If it is a ConnectionType then you called the wrong rpcRecv (call rpcRecv with a connection).");
					}
				}
			}
		}
	}
	
	void rpcRecv(RPCSrc src)(ConnectionType!src connection, const(ubyte)[] data){//// if (!is(ConnectionType!(RPCSrc, src) == typeof(null))) {
		enum ids = rpcIDs!(typeof(this));
		ubyte msgID = Serializer.deserialize!ubyte(data);
		static foreach(id; ids) {
			if (msgID == id) {
				alias rpcTemplate = rpcByID!(typeof(this),id);
				static if (is(typeof(rpcTemplate!src))) {
					alias rpc = rpcFunction!((Parameters!(rpcTemplate!src) args)=>rpcTemplate!src(args), ConnectionType!src);
					alias Params = Parameters!rpc[0..$-1];
					Params args;
					scope (success)
						rpc(args, connection);
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
			static if (!(is(MakeRPCs_Serializer) || is(typeof(MakeRPCs_Serializer))))
				alias MakeRPCs_Serializer = T;
			else static assert(false);
		}
	}
	static if (!is(MakeRPCs_RPCSrc)) {
		alias MakeRPCs_RPCSrc = RPCSrc;
	}
	static if (!is(MakeRPCs_RPCTrgt)) {
		static if (is(typeof(This.rpcSend)))
			alias MakeRPCs_RPCTrgt = MakeRPCs_RPCSrc;
		else
			enum MakeRPCs_RPCTrgt = null; 
		////static assert(is(typeof(rpcSend!(rvalueOf!RPCTrgt))), "`rpcSend` is undefined, but not right, rpcSend must be: `void rpcSend(RPCTrgt trgts)(...)`.  Either give an appropriate RPCTrgt (pass a second enum to `MakeRPCs`) or `rpcSend` should work with `RPCSrc`.");
	}
	
	static if (!(is(MakeRPCs_Serializer) || is(typeof(MakeRPCs_Serializer)))) {
		alias MakeRPCs_Serializer = Serializer!();
	}
	
	//---This section is necessary because of some bug, without this `ConnectionType` will not see the UDAs attached the the enum members.
	template ExtractConnectionTypes(E, size_t i) {
		static if (i < EnumMembers!E.length)
			alias ExtractConnectionTypes = AliasSeq!(ConnectionType!(EnumMembers!E[i]), ExtractConnectionTypes!(E, i+1));
		else
			alias ExtractConnectionTypes = AliasSeq!();
	}
	
	alias RPCSrcConnectionTypes = ExtractConnectionTypes!(MakeRPCs_RPCSrc, 0);
	static if (!is(typeof(MakeRPCs_RPCTrgt) == typeof(null))) {
		alias RPCTrgtConnectionTypes = ExtractConnectionTypes!(MakeRPCs_RPCTrgt, 0);
	}
	else {
		enum RPCTrgtConnectionTypes = null;
	}
	//---
	
	alias MakeRPCsArgs = AliasSeq!(MakeRPCs_RPCSrc, MakeRPCs_RPCTrgt, MakeRPCs_Serializer);
}

mixin template MakeRPCs(Ts...) {
	mixin MakeRPCsImpl!(MakeRPCsArgs!(typeof(this),Ts));
}

// Fixer for D bug #20835
enum enumMemberUDAFixMixin(string enumName) = q{
	static foreach(i; 0..EnumMembers!}~enumName~q{.length)
		pragma(msg, __traits(getAttributes, EnumMembers!}~enumName~q{[i]));
};

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
	enum RPCSrc {
		self	= 0x1,
		@RPCCon!Connection remote	= 0x2,
	}
	mixin(enumMemberUDAFixMixin!"RPCSrc");// Necessary because of D bug #20835
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
		mixin MakeRPCs!(RPCSrc);
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
}
unittest {
	pragma(msg, "Compiling Test C");
	import std.stdio;
	writeln("Running Test C");
	import std.exception;
	import std.conv;
	
	string lastMsg = "";
	const(ubyte)[] lastSendData = [];
	class A {
		void rpcSend(RPCSrc src)(const(ubyte)[] data) {
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
	const(ubyte)[] lastSendData = [];
	class A {
		void rpcSend(RPCSrc src)(const(ubyte)[] data) {
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
	const(ubyte)[] lastSendData = [];
	class Connection {}
	enum RPCSrc {
		self	= 0x1,
		@RPCCon!Connection remote	= 0x2,
	}
	mixin(enumMemberUDAFixMixin!"RPCSrc");// Necessary because of D bug #20835
	class A {
		void rpcSend(RPCSrc trgt:RPCSrc.self)(const(ubyte)[] data) {
			lastSendData = data;
		}
		void rpcSend(RPCSrc trgt:RPCSrc.remote)(Connection[] connections, const(ubyte)[] data) {
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
		mixin MakeRPCs!(RPCSrc);
	}
	pragma(msg, ConnectionType!(RPCSrc.remote));
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
	pragma(msg, "Compiling Test Fa");
	import std.stdio;
	writeln("Running Test Fa");
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
	
	const(ubyte)[] lastSendData = [];
	string lastMsg = "";
	class A {
		void rpcSend(Trgt trgts)(const(ubyte)[] data) {
			lastSendData = data;
		}
		@RPC
		void msg(Src src)(int x) {
			lastMsg = "msg: "~src.to!string~" - "~x.to!string;
		}
		mixin MakeRPCs!(Src, Trgt);
	}
	A a = new A;
	a.msg_send!(Trgt.server)(5);
	assert(lastSendData == [0, 5,0,0,0]);
}
unittest {
	pragma(msg, "Compiling Test Fb");
	import std.stdio;
	writeln("Running Test Fb");
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
	
	const(ubyte)[] lastSendData = [];
	string lastMsg = "";
	class A {
		void rpcSend(Trgt trgts)(const(ubyte)[] data) {
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
enum defaultSrcMixin(string name, string src) {
	return "ReturnType!("~name~"!("~src~")) "~name~"(Parameters!("~name~"!("~src~")) args) {
		return "~name~"!("~src~")(args);
	}";
}
unittest {
	pragma(msg, "Compiling Test G");
	import std.stdio;
	writeln("Running Test G");
	import std.exception;
	import std.conv;
	
	string lastMsg = "";
	class Connection {}
	enum RPCSrc {
		self	= 0x1,
		@RPCCon!Connection remote	= 0x2,
	}
	mixin(enumMemberUDAFixMixin!"RPCSrc");// Necessary because of D bug #20835
	class A {
		@RPC
		void msg(RPCSrc src)(ConnectionParam!src con, int x) {
			lastMsg = "msg: "~src.to!string~" - "~x.to!string;
		}
		mixin(defaultSrcMixin("msg","RPCSrc.self"));
		mixin MakeRPCs!(RPCSrc);
	}
	A a = new A;
	a.msg!(RPCSrc.self)(5);
	assert(lastMsg == "msg: self - 5");
	a.msg!(RPCSrc.remote)(new Connection, 5);
	assert(lastMsg == "msg: remote - 5");
	a.msg(5);
	assert(lastMsg == "msg: self - 5");
	a.rpcRecv!(RPCSrc.remote)(new Connection(), 0 ~ serialize(1));
	assert(lastMsg == "msg: remote - 1");
}
unittest {
	pragma(msg, "Compiling Test H");
	import std.stdio;
	writeln("Running Test H");
	import std.exception;
	import std.conv;
	
	string lastMsg = "";
	const(ubyte)[] lastSendData = [];
	class Connection {}
	enum RPCSrc {
		self	= 0x1,
		@RPCCon!Connection remote	= 0x2,
	}
	mixin(enumMemberUDAFixMixin!"RPCSrc");// Necessary because of D bug #20835
	class A {
		void rpcSend(RPCSrc trgt:RPCSrc.self)(const(ubyte)[] data) {
			lastSendData = data;
		}
		void rpcSend(RPCSrc trgt:RPCSrc.remote)(Connection[] connections, const(ubyte)[] data) {
			lastSendData = data;
		}
		@RPC
		void msg(RPCSrc src=RPCSrc.self)(int x) {
			lastMsg = "msg2: "~src.to!string~" - "~x.to!string;
		}
		mixin MakeRPCs!(RPCSrc);
	}
	pragma(msg, ConnectionType!(RPCSrc.remote));
	A a = new A;
	a.msg_send!(RPCSrc.self)(5);
	assert(lastSendData == [0,5,0,0,0]);
	a.msg_send!(RPCSrc.remote)([new Connection], 5);
	assert(lastSendData == [0,5,0,0,0]);
	a.msg_send!(RPCSrc.self|RPCSrc.remote)([new Connection], 5);
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

template ArrayExpand(alias array) {
	static if (array.length)
		alias ArrayExpand = AliasSeq!(array[0], ArrayExpand!(array[1..$]));
	else
		alias ArrayExpand = AliasSeq!();
}
template AliasLambda(string f) {
	template AliasLambda(T) {
		alias AliasLambda = mixin(f);
	}
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

 
