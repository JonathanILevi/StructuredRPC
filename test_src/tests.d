module tests;

import structuredrpc;
import treeserial;

import std.stdio;
import std.exception;
import std.conv;

unittest {
	pragma(msg, "Compiling Test Receive");
	writeln("Running Test Receive");
	
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
	pragma(msg, "Compiling Test Receive w/ Connection");
	writeln("Running Test Receive w/ Connection");
	
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
	pragma(msg, "Compiling Test Split-src Receive");
	writeln("Running Test Split-src Receive");
	
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
	pragma(msg, "Compiling Test Send");
	writeln("Running Test Send");
	
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
	pragma(msg, "Compiling Test Split-src Send");
	writeln("Running Test Split-src Send");
	
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
	pragma(msg, "Compiling Test Different Send");
	writeln("Running Test Different Send");
	
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
unittest {
	pragma(msg, "Compiling Test Template-src Receive");
	writeln("Running Test Template-src Receive");
	
	enum SrcA;
	enum SrcB;
	
	string lastMsg = "";
	class A {
		@RPC!SrcA
		@RPC!SrcB
		void msg(Src)(int x) {
			static if (is(Src==SrcA))
				lastMsg = "msg: a - "~x.to!string;
			static if (is(Src==SrcB))
				lastMsg = "msg: b - "~x.to!string;
		}
		mixin MakeRPCReceive!SrcA;
		mixin MakeRPCReceive!SrcB;
	}
	A a = new A;
	a.rpcRecv!SrcA(0 ~ serialize(1));
	assert(lastMsg == "msg: a - 1");
	a.rpcRecv!SrcB(0 ~ serialize(1));
	assert(lastMsg == "msg: b - 1");
}
unittest {
	pragma(msg, "Compiling Test Send in Receive");
	writeln("Running Test Send in Receive");
	
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
			msg_send!Src(5);
		}
		mixin MakeRPCReceive!Src;
		mixin MakeRPCSend!Src;
	}
	A a = new A;
	a.rpcRecv!Src(0 ~ serialize(1));
	assert(lastMsg == "msg: 1");
	assert(lastSendData == [0,5,0,0,0]);
}
unittest {
	pragma(msg, "Compiling Test Send in Template Receive");
	writeln("Running Test Send in Template Receive");
	
	enum Src;
	
	string lastMsg = "";
	const(ubyte)[] lastSendData = [];
	class A {
		@RPCSend!Src
		void rpcSend(const(ubyte)[] data) {
			lastSendData = data;
		}
		@RPC!Src
		void msg(S)(int x) {
			lastMsg = "msg: "~x.to!string;
			msg_send!Src(5);
		}
		mixin MakeRPCReceive!Src;
		mixin MakeRPCSend!Src;
	}
	A a = new A;
	a.rpcRecv!Src(0 ~ serialize(1));
	assert(lastMsg == "msg: 1");
	assert(lastSendData == [0,5,0,0,0]);
}
unittest {
	pragma(msg, "Compiling Test Different Send in Template Receive");
	writeln("Running Test Different Send in Template Receive");
	
	enum Src;
	class Client {}
	
	string lastMsg = "";
	const(ubyte)[] lastSendData = [];
	class ClientClass() {
		@RPC!Src
		void msg(S)(int x) {
			lastMsg = "msg: "~x.to!string;
			msg2_send!Src(x+1);
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
		void msg2(S)(int x, Client client) {
			lastMsg = "msg2: "~x.to!string;
			msg_send!Src([client], x+1);
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
	
	c.rpcRecv!Src([0,1,0,0,0]);
	assert(lastMsg == "msg: 1");
	assert(lastSendData == [0, 0,2,0,0,0]);
	
	s.rpcRecv!Src(new Client, [0,3,0,0,0]);
	assert(lastMsg == "msg2: 3");
	assert(lastSendData == [1, 0,4,0,0,0]);
}

 
