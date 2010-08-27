module luad.conversions.classes;

import luad.c.all;
import luad.stack;

import std.string : toStringz;

private void pushMeta(T)(lua_State* L, T o)
{
	lua_newtable(L); //get object metatable
	
	pushValue(L, T.mangleof);
	lua_setfield(L, -2, "__dmangle");
	
	pushValue(L, T.stringof);
	lua_setfield(L, -2, "__dname");
	
	lua_newtable(L); //__index fallback table
	
	foreach(member; __traits(allMembers, T))
	{
		static if(member != "__ctor" && member != "Monitor" && member != "toHash" && //do not handle
			member != "toString" && member != "opEquals" && //give special care
			member != "opCmp" && //TODO: give special care
			__traits(compiles, mixin("o." ~ member)) && //is a public member?
			__traits(compiles, mixin("T." ~ member)) && //can check for isStaticFunction?
			!__traits(isStaticFunction, mixin("T." ~ member))) //is not a static function?
		{
			pragma(msg, member);
			pushValue(L, mixin("&o." ~ member));
			lua_setfield(L, -2, member);
		}
	}
	
	lua_setfield(L, -2, "__index");
	
	pushValue(L, &o.toString);
	lua_setfield(L, -2, "__tostring");
	
	pushValue(L, &o.opEquals);
	lua_setfield(L, -2, "__eq");
	
	lua_pushvalue(L, -1);
	lua_setfield(L, -2, "__metatable");
}

void pushClass(T)(lua_State* L, T o) if (is(T == class))
{	
	void** ud = cast(void**)lua_newuserdata(L, o.sizeof);
	*ud = cast(void*)o;
	
	pushMeta(L, o);

	lua_setmetatable(L, -2);
}

T getClass(T)(lua_State* L, int idx) if (is(T == class))
{
	if(lua_getmetatable(L, idx) == 0)
	{
		luaL_error(L, "attempt to get 'userdata: %p' as an Object", lua_topointer(L, idx));
	}
	
	lua_getfield(L, -1, "__dmangle"); //must be a D object
	
	static if(!is(T == Object)) //must be the right object
	{
		size_t manglelen;
		auto cmangle = lua_tolstring(L, -1, &manglelen);
		if(cmangle[0 .. manglelen] != T.mangleof)
		{
			lua_getfield(L, -2, "__dname");
			auto cname = lua_tostring(L, -1);
			luaL_error(L, "attempt to get class %s as a %s", cname, toStringz(T.stringof));
		}
	}
	lua_pop(L, 2); //metatable and metatable.__dmangle
	
	auto o = cast(Object)lua_touserdata(L, idx);
	return cast(T)o;
}

unittest
{
	lua_State* L = luaL_newstate();
	scope(success) lua_close(L);
	
	class A
	{
		public:
		int a;
		string s;
		
		this(int a, string s)
		{
			this.a = a, this.s = s;
		}
		
		string foo(){ return s; }
		
		int bar(int b)
		{
			return a += b;
		}
	}
	
	auto o = new A(2, "foo");
	pushClass(L, o);
	lua_setglobal(L, "a");
	
	pushClass(L, o);
	lua_setglobal(L, "b");
	
	pushValue(L, (A a)
	{
		//assert(a);
		//a.bar(2);
	});
	lua_setglobal(L, "func");
	
	luaL_openlibs(L);
	unittest_lua(L, `
		print("before:", a.bar(2))
		func(a)
		print("after:", a.bar(2))
	`, __FILE__);
}