import core.runtime;

unittest
{
	assert(Runtime.args[0] == "");
	assert(Runtime.args[0] == "", "some message");
	assert(Runtime.args[0] == Runtime.args[0]);
}

unittest
{
	assert(Runtime.args[0] == Runtime.args[0]);
}
