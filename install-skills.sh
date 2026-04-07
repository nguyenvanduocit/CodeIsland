#!/bin/bash
set -e

SKILLS_DIR=".claude/skills"
TEMP_DIR=$(mktemp -d)

echo "Installing skills to $SKILLS_DIR..."

# 1. TDD (mattpocock)
echo "=> tdd"
git clone --depth 1 https://github.com/mattpocock/skills.git "$TEMP_DIR/mattpocock-skills"
mkdir -p "$SKILLS_DIR/tdd"
cp "$TEMP_DIR/mattpocock-skills/tdd/"*.md "$SKILLS_DIR/tdd/"

# 2. Swift Concurrency (AvdLee)
echo "=> swift-concurrency"
git clone --depth 1 https://github.com/AvdLee/Swift-Concurrency-Agent-Skill.git "$TEMP_DIR/swift-concurrency"
mkdir -p "$SKILLS_DIR/swift-concurrency/references"
cp "$TEMP_DIR/swift-concurrency/swift-concurrency/"*.md "$SKILLS_DIR/swift-concurrency/"
cp "$TEMP_DIR/swift-concurrency/swift-concurrency/references/"*.md "$SKILLS_DIR/swift-concurrency/references/"

# 3. SwiftUI Expert (AvdLee)
echo "=> swiftui-expert"
git clone --depth 1 https://github.com/AvdLee/SwiftUI-Agent-Skill.git "$TEMP_DIR/swiftui-expert"
mkdir -p "$SKILLS_DIR/swiftui-expert/references"
cp "$TEMP_DIR/swiftui-expert/swiftui-expert-skill/"*.md "$SKILLS_DIR/swiftui-expert/"
cp "$TEMP_DIR/swiftui-expert/swiftui-expert-skill/references/"*.md "$SKILLS_DIR/swiftui-expert/references/"

# 4. Swift Testing Expert (AvdLee)
echo "=> swift-testing"
git clone --depth 1 https://github.com/AvdLee/Swift-Testing-Agent-Skill.git "$TEMP_DIR/swift-testing"
mkdir -p "$SKILLS_DIR/swift-testing/references"
cp "$TEMP_DIR/swift-testing/swift-testing-expert/"*.md "$SKILLS_DIR/swift-testing/"
cp "$TEMP_DIR/swift-testing/swift-testing-expert/references/"*.md "$SKILLS_DIR/swift-testing/references/"

# Cleanup
rm -rf "$TEMP_DIR"

echo ""
echo "Done! Installed skills:"
find "$SKILLS_DIR" -name "*.md" | sort
