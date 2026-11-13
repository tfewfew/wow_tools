-- Use Titan's independent source and native API contract.
TEST_FLAVOR = "titan"
dofile((TEST_ROOT or ".") .. "/addon/tests/ForeverCompatibility.Tests.lua")
