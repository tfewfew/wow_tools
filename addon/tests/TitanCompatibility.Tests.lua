-- Run the full settings/TOC suite against Titan's independent source and native API shape.
TEST_FLAVOR = "titan"
dofile((TEST_ROOT or ".") .. "/addon/tests/ForeverCompatibility.Tests.lua")
