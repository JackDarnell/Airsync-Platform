#!/bin/bash
# Test suite for the AirSync installer
# Following TDD: These tests should pass after we fix the installer

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

TESTS_PASSED=0
TESTS_FAILED=0

test_pass() {
    echo -e "${GREEN}✓${NC} $1"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

test_fail() {
    echo -e "${RED}✗${NC} $1"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

echo "AirSync Installer Test Suite"
echo "============================="
echo ""

# Test 1: Installer should not require GitHub access
echo "Test 1: Installer works without GitHub access"
if grep -q "github.com/JackDarnell" ../scripts/install.sh; then
    if grep -q "# Bundled source mode" ../scripts/install.sh; then
        test_pass "Installer has offline/bundled mode"
    else
        test_fail "Installer requires GitHub access (no offline mode)"
    fi
else
    test_pass "Installer does not reference GitHub"
fi

# Test 2: Shairport-sync configure should specify systemd directory
echo "Test 2: Shairport-sync systemd directory specified"
if grep -q "with-systemd" ../scripts/install.sh; then
    if grep -q "systemunitdir" ../scripts/install.sh; then
        test_pass "Systemd unit directory explicitly configured"
    else
        test_fail "Systemd flag used but unit directory not specified"
    fi
else
    test_pass "Systemd not configured (skipped)"
fi

# Test 3: Installer should handle missing source gracefully
echo "Test 3: Installer checks for source before building"
if grep -q "if.*Cargo.toml.*exists" ../scripts/install.sh || \
   grep -q "SOURCE_ARCHIVE" ../scripts/install.sh; then
    test_pass "Installer validates source availability"
else
    test_fail "Installer doesn't check for source before building"
fi

echo ""
echo "Test Results:"
echo "============="
echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
echo -e "${RED}Failed: $TESTS_FAILED${NC}"

if [ $TESTS_FAILED -gt 0 ]; then
    echo ""
    echo "Tests failing - this is expected (RED phase)"
    exit 1
else
    echo ""
    echo "All tests passing (GREEN phase)"
    exit 0
fi
