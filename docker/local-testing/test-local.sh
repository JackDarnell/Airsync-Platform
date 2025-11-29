#!/bin/bash
# AirSync Local Testing Script
# Test AirPlay pairing from macOS to Docker container

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🧪 AirSync Local Testing Environment${NC}"
echo "====================================="
echo ""

# Check if running on macOS
if [[ "$OSTYPE" != "darwin"* ]]; then
    echo -e "${YELLOW}⚠️  Warning: This script is designed for macOS${NC}"
    echo "   You can still run it, but mDNS discovery may not work as expected."
    echo ""
fi

# Check if Docker is running
if ! docker info &> /dev/null; then
    echo -e "${RED}Error: Docker is not running${NC}"
    echo "Please start Docker Desktop and try again."
    exit 1
fi

echo -e "${BLUE}Step 1: Building AirSync receiver container...${NC}"
echo ""
docker-compose build

echo ""
echo -e "${BLUE}Step 2: Starting AirSync receiver...${NC}"
echo ""
docker-compose up -d

echo ""
echo -e "${BLUE}Step 3: Waiting for services to start...${NC}"
sleep 8

echo ""
echo -e "${BLUE}Step 4: Checking AirPlay service discovery...${NC}"
echo ""

# Check if dns-sd is available (macOS built-in)
if command -v dns-sd &> /dev/null; then
    echo "Browsing for AirPlay services (5 second scan)..."
    echo ""
    timeout 5 dns-sd -B _airplay._tcp local. 2>&1 | grep -i "airsync\|airplay" || echo "(Scanning...)"
    echo ""
else
    echo -e "${YELLOW}dns-sd not found (this is unusual on macOS)${NC}"
fi

# Show container logs (last 20 lines)
echo ""
echo -e "${BLUE}Step 5: Container logs (last 20 lines):${NC}"
echo ""
docker-compose logs --tail=20

echo ""
echo -e "${GREEN}✅ AirSync receiver is running!${NC}"
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}How to Test AirPlay Pairing:${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "  1. Open Music, Spotify, or any audio app on macOS"
echo "  2. Click the AirPlay icon (🔊) in the menu bar or app"
echo "  3. Select 'AirSync Local Test' from the device list"
echo "  4. Play audio and verify pairing works"
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}Useful Commands:${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "  ${YELLOW}View live logs:${NC}"
echo "    docker-compose logs -f"
echo ""
echo "  ${YELLOW}Restart receiver:${NC}"
echo "    docker-compose restart"
echo ""
echo "  ${YELLOW}Stop receiver:${NC}"
echo "    docker-compose down"
echo ""
echo "  ${YELLOW}Browse for AirPlay devices:${NC}"
echo "    dns-sd -B _airplay._tcp local."
echo ""
echo "  ${YELLOW}Enter container shell:${NC}"
echo "    docker-compose exec airsync-receiver bash"
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "Press Ctrl+C to stop this script (receiver keeps running)"
echo ""

# Offer to tail logs
read -p "Show live logs? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    echo -e "${BLUE}Following logs (Ctrl+C to exit):${NC}"
    echo ""
    docker-compose logs -f
fi
