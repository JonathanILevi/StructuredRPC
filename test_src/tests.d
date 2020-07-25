module tests;

import structuredrpc;
import treeserial;

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
unittest {
	pragma(msg, "Compiling Test F");
	import std.stdio;
	writeln("Running Test F");
	import std.exception;
	import std.conv;
	
	enum Src;
	class Client {}
	
	string lastMsg = "";
	const(ubyte)[] lastSendData = [];
	class ClientClass() {
		@RPC!Src
		void msg(int x) {
			lastMsg = "msg: "~x.to!string;
		}
		mixin MakeRPCReceive!(Src);
		
		@RPCSend!Src
		void rpcSend(const(ubyte)[] data) {
			lastSendData = 0~data;
		}
		mixin MakeRPCSendTo!(ServerClass!(), Src, Client);
	}
	class ServerClass() {
		@RPC!Src
		void msg2(int x, Client client) {
			lastMsg = "msg2: "~x.to!string;
		}
		mixin MakeRPCReceive!(Src, Client);
		
		@RPCSend!Src
		void rpcSend(Client[] clients, const(ubyte)[] data) {
			lastSendData = 1~data;
		}
		mixin MakeRPCSendTo!(ClientClass!(), Src);
	}
	
	ClientClass!() c = new ClientClass!();
	ServerClass!() s = new ServerClass!();
	
	s.msg_send!Src([new Client], 1);
	assert(lastSendData == [1, 0,1,0,0,0]);
	c.rpcRecv!Src(lastSendData[1..$]);
	assert(lastMsg == "msg: 1");
	
	s.msg_send!Src(new Client, 5);
	assert(lastSendData == [1, 0,5,0,0,0]);
	c.rpcRecv!Src(lastSendData[1..$]);
	assert(lastMsg == "msg: 5");
	
	c.msg2_send!Src(5);
	assert(lastSendData == [0, 0,5,0,0,0]);
	s.rpcRecv!Src(new Client(), lastSendData[1..$]);
	assert(lastMsg == "msg2: 5");
}

 
