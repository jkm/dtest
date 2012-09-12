// Copyright Jens K. Mueller
//
import dtest;

// unittests for dtest
// provided external to allow running them with dtest
int a;

unittest
{
	import std.traits;
	auto filteredModules = filterModules!((m) => withUnittests(m) &&
	    // additionally exclude this module to avoid infinite loop
	    m.name != moduleName!(a))(modules);
	auto results = testModules(filteredModules);
	registerFormatter("console", &consoleFormatter);
	//formatResults(results);
}

// TODO
// I'm very ashamed for not providing more unittests
