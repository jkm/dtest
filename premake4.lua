solution "dtest"
	language       "D"
	location       (_OPTIONS["to"])
	targetdir      (_OPTIONS["to"])
	flags          { "ExtraWarnings", "Symbols" }
	buildoptions   { "-wi" }
	configurations { "Optimize", "Tests" }
	platforms      { "Native", "x32", "x64" }
	files          { "src/dtest.d" }

	configuration "linux"
		linkoptions    { "-L--wrap=_d_throwc" }

	configuration "*Optimize*"
		flags          { "Optimize" }
		buildoptions   { "-noboundscheck", "-inline" }

	configuration "*Tests*"
		buildoptions   { "-unittest" }

	project "dtest"
		kind              "ConsoleApp"
		files             { "docs/*.d*" }
		files             { "src/dtest_unittest.d" }
		buildoptions      { "-Dddocs/html" }

		-- documentation
		postbuildcommands { string.format("cp -a %s/docs/bootDoc/assets/* docs/html/", os.getcwd()) }
		postbuildcommands { string.format("cp -a %s/docs/bootDoc/bootdoc.css docs/html/", os.getcwd()) }
		postbuildcommands { string.format("cp -a %s/docs/bootDoc/bootdoc.js docs/html/", os.getcwd()) }
		postbuildcommands { string.format("cp -a %s/docs/bootDoc/ddoc-icons docs/html/", os.getcwd()) }

		postbuildcommands { "./dtest --output=xml" }

	project "libdtest"
		kind              "StaticLib"
		targetname        "dtest"

	project "failing"
		kind              "ConsoleApp"
		files             { "tests/*.d" }

	newoption {
		trigger = "to",
		value   = "path",
		description = "Set the output location for the generated files"
	}

	if _ACTION == "clean" then
		os.rmdir("obj")
		os.rmdir("docs/html")
	end
