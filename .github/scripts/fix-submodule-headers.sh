#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright 2026 suyu Emulator Project
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Some vendored submodule headers are committed with a hardcoded Windows path
# (e.g. C:/Users/...). Replace the generated forwarding header so Linux builds
# resolve the real boost headers instead.
set -euo pipefail

f="externals/dynarmic/externals/mcl/include/boost/variant.hpp"
if [ -f "$f" ] && grep -q 'C:/Users' "$f"; then
  printf '// Forwarding header\n#include <boost/variant/variant.hpp>\n#include <boost/variant/recursive_variant.hpp>\n#include <boost/variant/recursive_wrapper.hpp>\n#include <boost/variant/get.hpp>\n#include <boost/variant/apply_visitor.hpp>\n#include <boost/variant/static_visitor.hpp>\n#include <boost/variant/visitor_ptr.hpp>\n' > "$f"
fi
