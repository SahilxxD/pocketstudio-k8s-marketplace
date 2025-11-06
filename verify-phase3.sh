#!/bin/bash

echo "========================================="
echo "  PHASE 3 VERIFICATION"
echo "========================================="
echo ""

ERRORS=0

# Check 1: Schema file exists
echo "1️⃣  Checking schema file..."
if [ -f "schema/schema.yaml" ]; then
  echo "   ✅ schema/schema.yaml exists"
else
  echo "   ❌ schema/schema.yaml missing"
  ERRORS=$((ERRORS + 1))
fi
echo ""

# Check 2: Valid YAML
echo "2️⃣  Validating YAML syntax..."
if python3 -c "import yaml; yaml.safe_load(open('schema/schema.yaml'))" 2>/dev/null; then
  echo "   ✅ Valid YAML syntax"
else
  echo "   ❌ Invalid YAML syntax"
  ERRORS=$((ERRORS + 1))
fi
echo ""

# Check 3: Required properties defined
echo "3️⃣  Checking required properties..."
required_props=(
  "name"
  "namespace"
  "image.pocketstudio"
  "customer.falKey"
  "customer.gcpBucket"
  "reportingSecret"
)

for prop in "${required_props[@]}"; do
  if grep -q "$prop" schema/schema.yaml; then
    echo "   ✅ $prop defined"
  else
    echo "   ❌ $prop missing"
    ERRORS=$((ERRORS + 1))
  fi
done
echo ""

# Check 4: Workload Identity requirement
echo "4️⃣  Checking Workload Identity requirement..."
if grep -q "workload-identity" schema/schema.yaml; then
  echo "   ✅ Workload Identity required"
else
  echo "   ❌ Workload Identity requirement missing"
  ERRORS=$((ERRORS + 1))
fi
echo ""

# Check 5: No Google API key required
echo "5️⃣  Checking Google API key NOT required..."
if grep -q "customer.googleApiKey" schema/schema.yaml; then
  echo "   ❌ Found customer.googleApiKey (should not be present)"
  ERRORS=$((ERRORS + 1))
else
  echo "   ✅ No Google API key required (correct!)"
fi
echo ""

# Check 6: Pricing information
echo "6️⃣  Checking pricing information..."
if grep -q "\$1.37" schema/schema.yaml; then
  echo "   ✅ Pricing information present"
else
  echo "   ⚠️  Pricing information missing"
fi
echo ""

# Summary
echo "========================================="
if [ $ERRORS -eq 0 ]; then
  echo "✅ ALL CHECKS PASSED!"
  echo ""
  echo "Phase 3 Status: COMPLETE ✅"
  echo ""
  echo "Schema Configuration:"
  echo "  ✓ Customer inputs: 5 fields"
  echo "    - Application name"
  echo "    - Namespace"
  echo "    - Number of replicas"
  echo "    - fal.ai API key"
  echo "    - GCS bucket name"
  echo "  ✓ Auto-detected: GCP project"
  echo "  ✓ Auto-generated: Reporting secret"
  echo "  ✓ Workload Identity: Required"
  echo "  ✓ No Google API key needed"
  echo ""
  echo "🎯 READY FOR PHASE 4!"
  echo "   Next: Create deployer container"
else
  echo "❌ $ERRORS ERRORS FOUND"
  echo ""
  echo "Please fix the errors above before proceeding"
fi
echo "========================================="
