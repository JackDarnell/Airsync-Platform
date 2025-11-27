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

# Test 4: Installer should have GitHub fallback for online installs
echo "Test 4: Installer can download from GitHub as fallback"
if grep -q "git clone.*Airsync-Platform" ../scripts/install.sh; then
    test_pass "Installer has GitHub download fallback"
else
    test_fail "Installer missing GitHub download fallback"
fi

# Test 5: Installer should install systemd service even in fallback mode
echo "Test 5: Installer handles systemd service in fallback mode"
if grep -q "make install || {" ../scripts/install.sh; then
    # Check if fallback block handles systemd service file
    if grep -A 20 "make install || {" ../scripts/install.sh | grep -q "shairport-sync.service"; then
        test_pass "Fallback mode installs systemd service file"
    else
        test_fail "Fallback mode doesn't install systemd service file"
    fi
else
    test_pass "No fallback mode (direct install)"
fi

# Test 6: Installer should check for systemd service when shairport-sync exists
echo "Test 6: Installer verifies systemd service when binary exists"
if grep -q "shairport-sync already installed" ../scripts/install.sh; then
    # Check if there's logic to verify/install systemd service even when binary exists
    if grep -A 5 "shairport-sync already installed" ../scripts/install.sh | grep -q "install_shairport_service"; then
        test_pass "Installer checks systemd service when binary exists"
    else
        test_fail "Installer skips systemd service check when binary exists"
    fi
else
    test_pass "No early return for existing binary"
fi

# Test 7: Installer should install NQPTP for AirPlay 2
echo "Test 7: Installer includes NQPTP for AirPlay 2"
if grep -q "install_nqptp\|NQPTP\|nqptp" ../scripts/install.sh; then
    test_pass "Installer includes NQPTP installation"
else
    test_fail "Installer missing NQPTP (required for AirPlay 2)"
fi

# Test 8: Installer should build with AirPlay 2 support
echo "Test 8: Installer configures shairport-sync with AirPlay 2"
if grep -q "\\-\\-with-airplay-2" ../scripts/install.sh; then
    test_pass "Installer includes --with-airplay-2 flag"
else
    test_fail "Installer missing --with-airplay-2 flag"
fi

# Test 9: Installer should install AirPlay 2 dependencies
echo "Test 9: Installer includes AirPlay 2 dependencies"
if grep -q "libplist-dev" ../scripts/install.sh && \
   grep -q "libsodium-dev" ../scripts/install.sh && \
   grep -q "libavcodec-dev" ../scripts/install.sh; then
    test_pass "Installer includes AirPlay 2 dependencies"
else
    test_fail "Installer missing AirPlay 2 dependencies (libplist, libsodium, ffmpeg)"
fi

# Test 10: Installer should detect and allow selection of audio devices
echo "Test 10: Installer detects and prompts for audio device selection"
if grep -q "aplay -L\|list.*audio.*device\|select.*audio" ../scripts/install.sh; then
    test_pass "Installer includes audio device detection/selection"
else
    test_fail "Installer doesn't detect/prompt for audio device selection"
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
