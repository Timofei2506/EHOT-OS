#!/usr/bin/env bash
set -euo pipefail

# EHOT OS Gaming Hardware & Compatibility Checker (`ehot-game-check`)
# Inspects CPU flags, RAM/ZRAM, GPU OpenGL/Vulkan, and reports honest compatibility
# for Steam/Proton, Minecraft, and Roblox (Sober).

echo "=== EHOT OS: Диагностика игровой совместимости ==="
echo

echo "[1/5] Процессор и инструкции (SSE4.1 / AVX):"
if grep -qw "sse4_1" /proc/cpuinfo 2>/dev/null; then
  echo "  - SSE4.1: ПОДДЕРЖИВАЕТСЯ"
else
  echo "  - SSE4.1: НЕ ОБНАРУЖЕНО (Sober для Roblox не запустится)"
fi
if grep -qw "avx" /proc/cpuinfo 2>/dev/null; then
  echo "  - AVX: ПОДДЕРЖИВАЕТСЯ"
else
  echo "  - AVX: нет (современные AAA-игры через Proton могут требовать AVX)"
fi

echo
echo "[2/5] Оперативная память, ZRAM и Swap:"
free -h
if command -v zramctl >/dev/null 2>&1; then
  zramctl || true
fi

echo
echo "[3/5] Видеокарта и OpenGL / Vulkan:"
if command -v glxinfo >/dev/null 2>&1; then
  glxinfo -B 2>/dev/null | grep -E "OpenGL vendor|OpenGL renderer|OpenGL version" || echo "  - X11 дисплей недоступен в текущей консоли"
fi
if command -v vulkaninfo >/dev/null 2>&1; then
  if vulkaninfo --summary 2>/dev/null | head -n 25; then
    echo "  - Vulkan: ДОСТУПЕН"
  else
    echo "  - Vulkan: НЕДОСТУПЕН (для Proton используйте PROTON_USE_WINED3D=1)"
  fi
else
  echo "  - vulkaninfo не установлен"
fi

echo
echo "[4/5] Игровые инструменты:"
for tool in steam lutris wine winetricks gamemoded mangohud flatpak java; do
  if command -v "$tool" >/dev/null 2>&1; then
    echo "  - $tool: OK"
  else
    echo "  - $tool: не найден"
  fi
done

echo
echo "[5/5] Важная справка по Roblox и Minecraft:"
echo "  * Minecraft Launcher намеренно не предустановлен. Java готова; лаунчер устанавливается владельцем вручную."
echo "  * Roblox ОФИЦИАЛЬНО НЕ ПОДДЕРЖИВАЕТСЯ на Linux. Wine/Proton (Vinegar) не работают с 2024 года из-за античита Hyperion."
echo "  * Неофициальная опция сообщества — Sober (Flatpak org.vinegarhq.Sober), требует SSE4.1 и Vulkan 1.1/OpenGL ES 3.0."
echo "  * Гарантированная работа Roblox не обещается; обход античита не применяется."
