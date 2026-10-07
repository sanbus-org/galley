"""Shared names for the Python binding.

The inner extension filename, its baked ``PyInit`` entry, and the
loader's module name must agree or bare loads fail. One constant owns
all three: the build passes it to the compiler
(``-DGALLEY_MODULE_NAME``) and names the file with it, the loader
creates the module under it.
"""

IMPL_MODULE_NAME = "galley_impl"
