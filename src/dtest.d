// Copyright Jens K. Mueller
/**
 * dtest is an easy to use test runner for D modules.
 * Its aim is to provide easy access to the test results and formatting them.
 *
 * You can use dtest in the following ways:
 * $(UL
 *   $(LI Build with the modules to test and run from command line
 *
 *     $(TT $ dmd -unittest path/to/modules/*.d path/to/dtest.d -ofdtest)
 *     $(BR)
 *     $(TT $ ./dtest)
 *
 *   or via dmd's run option
 *
 *     $(TT $ dmd -unittest path/to/modules/*.d -run path/to/dtest.d)
 *     $(BR)
 *     E.g. to test all of $(LINK_TEXT http://dlang.org/phobos/index.html, Phobos)
 *     $(BR)
 *     $(TT $ dmd -unittest path/to/phobos/std/**.d -run path/to/dtest.d)
 *
 *   )
 *   $(LI Use as a library driving the testing yourself
 *   ---
 *   import dtest;
 *
 *   auto filteredModules = filterModules!((m) => withUnittests(m))(modules);
 *   auto results = testModules(filteredModules);
 *   registerFormatter("console", &consoleFormatter);
 *   formatResults(results);
 *   ---
 *   Don't forget to link against libdtest.
 *   )
 * )
 * dtest provides out-of-the-box integration for
 * $(LINK_TEXT http://jenkins-ci.org/, Jenkins) and similar tools output by
 * outputting JUnit-compatible XML output (see
 * $(LOCAL_LINK_TEXT xmlFormatterAnchor, xmlFormatter)).
 * E.g. this output for dtest is available at
 * $(LINK_TEXT https://buildhive.cloudbees.com/job/jkm/job/$(PROJECTNAME)/lastCompletedBuild/testReport/history/, buildhive).
 *
 * When using GNU ld for linking then aborting/breaking on any Throwable is
 * configurable. On Windows aborting/breaking can only be configured for
 * asserts.
 *
 * $(B This module is written such that is should work on Windows but has been
 * only compiled and tested on Linux. Please report any issue while trying it
 * out.)
 *
 * Bugs: $(ISSUES)
 * License: $(LICENSE)
 * Version: $(VERSION) ($(B alpha release))
 * Date: $(DATE)
 */
module dtest;
enum VERSION = 0.1;

import core.runtime;
import core.exception;

import std.algorithm;
import std.stdio;
import std.conv;
import std.regex;
import std.format;
import std.array;

/// Returns: an array of ModuleInfo* for known modules.
@property
ModuleInfo*[] modules()
{
	auto app = appender!(ModuleInfo*[])();
	foreach (m; ModuleInfo) app.put(m);
	return app.data;
}

/// Returns: a subset of the given modules by applying pred as a filter.
ModuleInfo*[] filterModules(alias pred)(ModuleInfo*[] modules)
{
	auto filteredModules = modules.filter!pred().array();
	return filteredModules;
}

/// Returns: true iff ModuleInfo defines unittests and is not this module.
bool withUnittests(ModuleInfo* m)
{
	import std.traits;
	return m.name != moduleName!(TestResult) && m.unitTest;
}

/// Returns: an InputRange of TestResult for each given module. This range is
/// lazy.
auto testModules(ModuleInfo*[] modules)
{
	return map!((m) => executeUnittests(m))(modules);
}

/// Execute unittests for given module.
TestResult executeUnittests(ModuleInfo* m)
in
{
	assert(m !is null);
	assert(m.unitTest !is null);
}
body
{
	TestResult res = TestResult(m);
	import std.datetime;
	StopWatch sw;
	failures = [];
	errors = [];

	try
	{
		sw.start();
		m.unitTest()();
	}
	catch (AssertError e)
	{
		failures ~= e;
	}
	catch (Throwable e)
	{
		errors ~= e;
	}
	finally
	{
		sw.stop();
	}
	res.failures ~= failures;
	res.errors ~= errors;
	res.executionTime = sw.peek();

	return res;
}

/// Stores the test results for a single module.
struct TestResult
{
	import core.time;
	/// ModuleInfo of the tested module
	ModuleInfo* moduleInfo;
	/// all (assert) failures
	AssertError[] failures;
	/// all other errors (like unhandled exceptions)
	Throwable[] errors;
	/// duration to execute the tests
	TickDuration executionTime;

	/// Constructs an empty TestResult from given ModuleInfo
	this(ModuleInfo* m) nothrow
	in
	{
		assert(m != null);
	}
	body
	{
		moduleInfo = m;
	}

	/// Returns: true, iff there are failures or errors.
	@property
	bool failed() nothrow pure { return !failures.empty || !errors.empty; }
}

/// A Formatter formats TestResult. That is, it converts the TestResults for
/// one kind of output.
alias void function(TestResult[]) Formatter;

/// Register a given Formatter under the given name.
void registerFormatter(string name, Formatter f) nothrow
{
	formatter[name] = f;
}

/// Unregister the Formatter registered by the given name.
void unregisterFormatter(string name) nothrow
{
	formatter.remove(name);
}

/// Formats output for the console.
void consoleFormatter(TestResult[] results)
{
	auto console = consoleFile.lockingTextWriter();
	foreach (res; results)
	{
		with(res)
		{
			enum Messages = ["FAIL", "PASS"];
			console.formattedWrite("%s %s", Messages[!failed], moduleInfo.name);
			if (_flags.printTime)
				console.formattedWrite(" (took %s ms)", executionTime.msecs);
			console.formattedWrite("\n");

			foreach (t; chain(failures, errors))
				console.formattedWrite(formatThrowable(t));
		}
	}
}

/// Returns: a string that formats the given Throwable.
string formatThrowable(Throwable t)
{
	import std.string;
	return format("%s@%s(%s): %s\n", t.classinfo.name, t.file, t.line, t.msg) ~
	       (t.next !is null ? "  " ~ formatThrowable(t.next) : "") ~
		   (_flags.backtrace ? formatBacktrace(t) : "");
}

/// Returns: a string that formats the given Throwable's backtrace.
string formatBacktrace(Throwable t)
{
	string result = "------\n";
	foreach (frame; t.info)
	{
		result ~= frame ~ "\n";
	}
	return result;
}

// due to BUG 8586
// import must be here
import std.xml;
import std.socket;
/// $(ANCHOR xmlFormatterAnchor)
/// Formats XML output. The format is compatible with Apache Ant's (1.8.2) JUnit
/// task and JUnitReport task
/// (see $(LINK_TEXT http://windyroad.org/dl/Open%20Source/JUnit.xsd, JUnit.xsd)).
void xmlFormatter(TestResult[] results)
{
	auto a = new Element("testsuites");
	auto b = new Element("testsuite");
	b.tag.attr["id"] = "0";
	b.tag.attr["package"] = "";
	b.tag.attr["name"] = "some";
	import std.datetime;
	auto time = Clock.currTime();
	time.fracSec = FracSec.from!"msecs"(0);
	b.tag.attr["timestamp"] = time.toISOExtString();
	b.tag.attr["hostname"] = Socket.hostName();
	b.tag.attr["tests"] = to!string(results.length);
	b.tag.attr["failures"] = to!string(results.count!((r) => !r.failures.empty)());
	b.tag.attr["errors"] = to!string(results.count!((r) => !r.errors.empty)());
	b.tag.attr["time"] = to!string(reduce!((a, b) => a + b.executionTime)
	                                 (typeof(TestResult.executionTime).init, results).msecs);

	a.items ~= b;
	b ~= new Element("properties");

	foreach (res; results)
	{
		Element e = new Element("testcase");
		b ~= new Element("system-out");
		b ~= new Element("system-err");
		b ~= e;
		with(res)
		{
			e.tag.attr["classname"] = "";
			e.tag.attr["name"] = moduleInfo.name;
			e.tag.attr["time"] = to!string(executionTime.msecs);
			foreach (t; failures)
				e ~= new Element("failure", formatThrowable(t));
			foreach (t; errors)
				e ~= new Element("error", formatThrowable(t));
		}
	}
	a.pretty(4).joiner("\n").copy(File(_flags.output, "w").lockingTextWriter());
}

import std.range;
/// Applies all registered formatters to the given input range of TestResults.
void formatResults(R)(R results)
	if (isInputRange!R && is(ElementType!R == TestResult))
{
	foreach (f; formatter.byValue())
		f(results.array());
}

/// Disables the Runtime's module unittester.
/// $(B It is called on this modules construction. Ie. when this modules is
/// used the Runtime's module unittester won't be executed.)
void disableRuntimeModuleUnitTester()
{
	static bool nullModuleUnitTester()
	{
		return true;
	}
	Runtime.moduleUnitTester = &nullModuleUnitTester;
}

private:

static this()
{
	disableRuntimeModuleUnitTester();
}

static this()
{
	consoleFile = stdout;
}

Formatter[string] formatter; // hash of formatters
File consoleFile; // console output is sent here

/// Initialize testing
void initTesting(ref string[] args)
{
	_flags = Flags(args);
	assertHandler = &myAssertHandler;

	// register predefined formatters
	registerFormatter("console", &consoleFormatter);
	if (_flags.output)
		registerFormatter("xml", &xmlFormatter);

	if (_flags.quiet)
	{
		version(Posix)
			consoleFile = File("/dev/null", "w");
		else version(Windows)
			consoleFile = File("nul", "w");
		else static assert(false, NOT_IMPLEMENTED);
	}
}

/// Returns: true iff modules is explicitly included and not explicitly
/// excluded.
bool includeExcludeModule(ModuleInfo* m)
{
	// exclude wins over include
	return (!_flags.include || _flags.include.any!((f) => m.name.match(regex(f)))())
	       && (!_flags.exclude || _flags.exclude.find!((f) => m.name.match(regex(f)))().empty);
}

// due to BUG 8586
// import must be here
import std.random;
int main(string[] args)
{
	initTesting(args);
	auto console = consoleFile.lockingTextWriter();

	auto filteredModules =
	  filterModules!((m) => withUnittests(m) && includeExcludeModule(m))(modules);

	if (filteredModules.empty)
	{
		console.formattedWrite("No modules to test.\n");
		return 0;
	}

	console.formattedWrite("Testing %s modules: %s\n", filteredModules.length,
	                      filteredModules.map!((m) => m.name)());

	// list module only
	if (_flags.list) return 0;

	Random rnd;
	if (_flags.shuffle)
	{
		auto seed = _flags.seed.isNull ? unpredictableSeed : _flags.seed;
		console.formattedWrite("Seeding with %s\n", seed);
		rnd = Random(seed);
	}

	auto numberLength = to!int(to!string(_flags.repeatCount).length);

	auto failedModules = appender!(string[])();
	foreach (i; 0 .. _flags.repeatCount)
	{
		console.formattedWrite("====== Run %*s of %*s ======\n",
		                      numberLength, i + 1, numberLength, _flags.repeatCount);
		if (_flags.shuffle) randomShuffle(filteredModules, rnd);

		// execute unittests
		TestResult[] results;
		results.length = filteredModules.length;
		testModules(filteredModules).copy(results);

		// remember failed modules
		failedModules.put(results.filter!((r) => r.failed)()
		                  .map!((r) => r.moduleInfo.name)());

		formatResults(results);
	}

	console.formattedWrite("======%s======\n",
	                      std.range.repeat("=", 10 + 2 * numberLength).joiner());

	if (!failedModules.data.empty)
	{
		auto failed = failedModules.data.sort().uniq();
		assert(failed.count() <= filteredModules.length);
		console.formattedWrite("Failed modules (%s of %s): %s\n",
		          failed.count(), filteredModules.length, to!string(failed));
		return 2;
	}

	console.formattedWrite("All modules passed: %s\n",
	                       filteredModules.map!((m) => m.name)());

	return 0;
}

enum NOT_IMPLEMENTED = "Not implemented for your OS. Please report.";

AssertError[] failures;
Throwable[] errors;

version(Posix)
{
	// wrap throwing function
	version(DigitalMars)
	{
		extern extern(C) void __real__d_throwc(Object* h);
		alias dThrow = __real__d_throwc;
		enum funcName = "__wrap__d_throwc";
	}
	else version(GNU)
	{
		extern extern(C) void __real__d_throw(Object* h);
		alias dThrow = __real__d_throw;
		enum funcName = "__wrap__d_throw";
	}
	else version(LLVM)
	{
		extern extern(C) void __real__d_throw_exception(Object* h);
		alias dThrow = __real__d_throw_exception;
		enum funcName = "__wrap__d_throw_exception";
	}
	else static assert(false, "unable to wrap _d_throw");

	mixin(format(q{
	extern(C) void %s(Object* h)
	{
		auto t = cast(Throwable) h;
		assert(t !is null);

		auto e = cast(AssertError) t;
		// decision for asserts was already made
		// if it reaches here pass it on
		if (e !is null) dThrow(h);

		if (_flags.breakpoint == Flags.Break.throwables ||
		    _flags.breakpoint == Flags.Break.both)
		{
			debugBreak();
			return;
		}

		if (_flags.abort == Flags.Abort.throwables || _flags.abort == Flags.Abort.both)
			dThrow(h);
		else
			errors ~= t;
	}
	}, funcName));
}

void myAssertHandler(string file, size_t line, string msg) nothrow
{
	if (_flags.breakpoint == Flags.Break.asserts ||
		_flags.breakpoint == Flags.Break.both)
	{
		debugBreak();
		return;
	}

	auto e = new AssertError(msg, file, line);
	if (_flags.abort == Flags.Abort.asserts || _flags.abort == Flags.Abort.both)
		throw e;
	else
		failures ~= e;
}

/// true iff break was performed.
void debugBreak() nothrow
{
	version(Posix)
	{
		import core.stdc.signal;
		import core.sys.posix.signal;
		raise(SIGTRAP);
	}
	else version(Windows)
	{
		DebugBreak();
	}
	else assert(false);
}

Flags _flags;

struct Flags
{
	enum Color { no, yes, automatic }
	enum {
		     DEFAULT_REPEAT_COUNT = 1,
		     DEFAULT_COLOR = Color.automatic,
		     DEFAULT_SHUFFLE = false,
		     DEFAULT_BACKTRACE = false,
		     DEFAULT_PRINT_TIME = false,
		     DEFAULT_QUIET = false,
		     DEFAULT_BREAKPOINT = false,
		     DEFAULT_NO_ABORT = false,
		     DEFAULT_XML = null,
	     }

	// due to BUG 8586
	// import must be here
	import std.getopt;
	this(ref string args[])
	{
		repeatCount = DEFAULT_REPEAT_COUNT;
		shuffle = DEFAULT_SHUFFLE;
		color = DEFAULT_COLOR;
		backtrace = DEFAULT_BACKTRACE;
		output = DEFAULT_XML;
		printTime = DEFAULT_PRINT_TIME;
		quiet = DEFAULT_QUIET;

		import core.stdc.stdlib;
		try getopt(args,
			       "list",        &list,
			       "include",     &include,
			       "exclude",     &exclude,
			       "repeat",      &repeatCount,
			       "shuffle",     &shuffle,
			       "seed",        (string option, string value) { seed = parse!(typeof(seed.get()))(value); },
			       "color",       &color,
			       "backtrace",   &backtrace,
			       "abort",       &this.abort,
			       "break",       &breakpoint,
			       "output",      &output,
			       "version",     delegate() { printVersion(); exit(0); },
			       "time",        &printTime,
			       "q|quiet",     &quiet,
			       "version",     delegate() { printVersion(); exit(0); },
			       "help",        delegate() { printUsage(); exit(0); }
			      );
		catch(std.conv.ConvException e)
		{
			stderr.writeln(e.msg);
			exit(1);
		}
		catch(Exception e)
		{
			stderr.writeln(e.msg);
			exit(1);
		}

		if (output)
		{
			import std.path;
			if (output.length < "xml".length || output[0 .. 3] != "xml" ||
			    output.length >= "xml:".length && output[3] != ':')
			{
				stderr.writeln("option --output must start with 'xml'"
				    "and optionally followed by ':' if a file/directory is passed");
				exit(1);
			}
			assert(output.length >= "xml".length);
			enum DEFAULT_FILENAME = "results.xml";
			output = output.length <= "xml:".length ? DEFAULT_FILENAME : output[4 .. $];

			if (!isValidFilename(output) && !isValidPath(output) || isDirSeparator(output[$ - 1]))
			{
				output = buildPath(output, DEFAULT_FILENAME);
			}

			assert(isValidPath(output));

			import std.file;
			if (exists(output)) {
				stderr.writefln("File '%s' already exists. Skipping.", output);
				exit(1);
			}
		}

		if (!seed.isNull && !shuffle)
			stderr.writefln("Warning: Given a seed but no --shuffle.");
	}

	void printUsage()
	{
		import std.traits;
		writeln("Usage: dtest [options]\n"
		        "Options:\n"
		        "  --list                              List tested modules names only.\n"
		        "  --include                           Add a pattern to include modules. If a module name matches\n"
				"                                      a pattern it will be included.\n"
		        "  --exclude                           Add a pattern to exclude modules. If a module name matches\n"
				"                                      a pattern it will be excluded. Exclude wins over include.\n"
		        "  --repeat=count                      Makes <count> runs over the tests. Defaults to ", DEFAULT_REPEAT_COUNT, ".\n"
		        "  --shuffle                           Random shuffle the execution order for each run.\n"
		        "  --seed=value                        Seed used for random the shuffle. Defaults to an unpredictable seed.\n"
		        "  --backtrace                         Add backtrace to console output.\n"
		        "  --time                              Print running time per module.\n"
		        "  --output=xml[:file|:directory]      Output results in XML to given file/directory.\n"
		        "  --abort=", to!string(map!(to!string)([EnumMembers!Abort]).joiner("|")),
		        "  Abort executing a module. Defaults to ", to!string(Abort.init) , ".\n"
		        "  --break=", to!string(map!(to!string)([EnumMembers!Break]).joiner("|")),
		        "  Break when executing a module. Defaults to ", to!string(Break.init), ".\n"
		        "  --color                             Use colored output. Defaults to automatic.\n"
		        "  --quiet                             Quiet. No output to console.\n"
		        "  --version                           Print the version.\n"
		        "  --help                              Print this help."
			   );
	}

	// due to BUG 8586
	// import must be here
	import std.path;
	void printVersion()
	{
		writeln(baseName(Runtime.args[0]), " v", VERSION);
	}

	private:
	version(Posix)
	{
		enum Abort { both, asserts, throwables, no }
		enum Break { no, asserts, throwables, both }
	}
	else version(Windows)
	{
		enum Abort { both, asserts, }
		enum Break { no, asserts, }
	}
	else static assert(false, NOT_IMPLEMENTED);

	bool list;
	string[] include;
	string[] exclude;
	size_t repeatCount;
	bool shuffle;
	import std.typecons : Nullable;
	Nullable!uint seed;
	Color color;
	bool backtrace;
	Abort abort;
	Break breakpoint;
	string output;
	bool printTime;
	bool quiet;
}
