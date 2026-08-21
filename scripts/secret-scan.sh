#!/usr/bin/env sh

# Scan the staged diff for secret-shaped strings:
#   - 32+ hex chars, with or without a `0x` prefix. Covers BJJ and
#     Ethereum private keys (64), 128-bit keys (32).
#   - 20+ digit decimal / bigint literals. Field elements and identity
#     secret keys are often carried in decimal.
#
# We allow only 40 hex chars (160-bit), the standard for Ethereum addresses
#
# Opt out per line with `// nosec: <reason>` (JS/TS) or `# nosec: <reason>`
# (shell, YAML, .env). The reason is required so bypasses stay auditable.

hits=$(git diff --cached --no-color -U0 -- . ':!*.lock' ':!package-lock.json' |
  grep -E '^\+' | grep -vE '^\+\+\+' |
  grep -ivE '(//|#) *nosec: *[A-Za-z0-9]' |
  perl -pe 's/\b(0x)?[a-fA-F0-9]{40}\b/<ETH_ADDRESS>/g' | # why perl ? on macOS sed ignores `\b`
  grep -iE '\b(0x)?[a-f0-9]{32,}\b|\b[0-9]{20,}n?\b')

[ -z "$hits" ] && exit 0

echo ""
echo "🚨  Secret-shaped string in staged diff:"
echo ""
echo "$hits" | head -5
echo ""
echo "   If it's a fixture, test vector or public value, append"
echo "   \`// nosec: <reason>\` (or \`# nosec: <reason>\`) to the line."
echo "   Commit aborted."
echo ""
exit 1
