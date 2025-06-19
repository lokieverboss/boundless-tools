#!/bin/bash

set -e  # 有错就退出

# 默认 RPC
DEFAULT_RPC="https://base.meowrpc.com"
RPC_URL="$DEFAULT_RPC"
PRIVATE_KEY=""
ENV_FILE=".env.base"

# ἟1 安装环境
function install_environment() {
  echo "🧱 正在安装开发环境..."

  echo "🔍 检查系统环境..."

  # 检查 cc 是否存在
  if ! command -v cc &>/dev/null; then
    echo "⚠️ 未检测到系统编译器 (cc)"
    UNAME=$(uname)
    if [ "$UNAME" = "Linux" ]; then
      if [ -f /etc/debian_version ]; then
        echo "🛠 安装 Debian 系列依赖..."
        sudo apt update && sudo apt install -y build-essential pkg-config libssl-dev curl git
      elif [ -f /etc/arch-release ]; then
        echo "🛠 安装 Arch 依赖..."
        sudo pacman -Syu --noconfirm base-devel openssl pkgconf curl git
      else
        echo "❌ 未支持的 Linux 发行版，请手动安装 cc make openssl pkg-config"
        exit 1
      fi
    else
      echo "❌ 未支持的操作系统：$UNAME"
      exit 1
    fi
  fi

  echo "✔️ 编译环境正常"

  echo "⬆️ 安装 Rust..."
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
  source "$HOME/.cargo/env"

  echo "⬆️ 安装 Risc0..."
  curl -L https://risczero.com/install | bash
  export PATH="$HOME/.risc0/bin:$PATH"
  echo 'export PATH="$HOME/.risc0/bin:$PATH"' >> "$HOME/.bashrc"
  source "$HOME/.bashrc"

  echo "⬆️ 安装 Risc0 toolchain..."
  rzup install
  rzup install rust

  echo "⬆️ 安装 bento-cli..."
  cargo install --git https://github.com/risc0/risc0 bento-client --bin bento_cli

  echo "⬆️ 安装 boundless-cli..."
  cargo install --locked boundless-cli --force

  echo "✅ 安装完成!"
}

function test_rpc() {
  echo "⏳ 正在测试 RPC..."
  RESPONSE=$(curl -s -X POST "$RPC_URL" -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}')
  if [[ "$RESPONSE" != *"result"* ]]; then
    echo "❌ RPC 连接失败"
    return 1
  else
    echo "✅ 成功，链ID：$(echo "$RESPONSE" | grep -o '"result":"[^"]*"' | cut -d':' -f2)"
    return 0
  fi
}

function write_env_file() {
  cat <<EOF > "$ENV_FILE"
ETH_RPC_URL=$RPC_URL
PRIVATE_KEY=$PRIVATE_KEY
VERIFIER_ADDRESS=0x0b144e07a0826182b6b59788c34b32bfa86fb711
BOUNDLESS_MARKET_ADDRESS=0x26759dbB201aFbA361Bec78E097Aa3942B0b4AB8
SET_VERIFIER_ADDRESS=0x8C5a8b5cC272Fe2b74D18843CF9C3aCBc952a760
ORDER_STREAM_URL=https://base-mainnet.beboundless.xyz
EOF
}

function config_menu() {
  while true; do
    echo "\n📌 当前 RPC: $RPC_URL"
    echo "🔐 私钥: $( [ -z "$PRIVATE_KEY" ] && echo '未设置' || echo '已设置')"
    echo "\n🛠 配置选项:"
    echo "1 - 设置 RPC"
    echo "2 - 设置私钥"
    echo "3 - 测试 RPC 并保存"
    echo "4 - 开始进行资金转入"
    echo "5 - 退出"
    read -p "请选择: " CHOICE
    case "$CHOICE" in
      1) read -p "新 RPC 地址: " INPUT; [ -n "$INPUT" ] && RPC_URL="$INPUT";;
      2) read -s -p "输入私钥: " INPUT; echo; [ -n "$INPUT" ] && PRIVATE_KEY="$INPUT";;
      3) test_rpc && write_env_file && echo "✅ 已保存配置";;
      4)
        if [ -z "$PRIVATE_KEY" ]; then echo "❌ 私钥未设置"; continue;
        elif ! test_rpc; then echo "❌ RPC 无效"; continue;
        else write_env_file; break;
        fi;;
      5) echo "退出"; exit 0;;
      *) echo "无效选项";;
    esac
  done
}

function staking_menu() {
  source "$ENV_FILE"
  while true; do
    echo "\n💰 选择进行操作:"
    echo "1 - 转入 USDC (资金转入)"
    echo "2 - 转入 ETH"
    echo "3 - 退出"
    read -p "选择功能: " STAKE_OPTION
    case "$STAKE_OPTION" in
      1)
        read -p "💵 USDC 量：" AMOUNT
        boundless --rpc-url "$ETH_RPC_URL" \
          --boundless-market-address "$BOUNDLESS_MARKET_ADDRESS" \
          --set-verifier-address "$SET_VERIFIER_ADDRESS" \
          --private-key "$PRIVATE_KEY" \
          --verifier-router-address "$VERIFIER_ADDRESS" \
          --order-stream-url "$ORDER_STREAM_URL" \
          account deposit-stake "$AMOUNT"
        echo "✅ 成功转入 USDC"
        ;;
      2)
        read -p "💵 ETH 量：" AMOUNT
        boundless --rpc-url "$ETH_RPC_URL" \
          --boundless-market-address "$BOUNDLESS_MARKET_ADDRESS" \
          --set-verifier-address "$SET_VERIFIER_ADDRESS" \
          --private-key "$PRIVATE_KEY" \
          --verifier-router-address "$VERIFIER_ADDRESS" \
          --order-stream-url "$ORDER_STREAM_URL" \
          account deposit "$AMOUNT"
        echo "✅ 成功转入 ETH"
        ;;
      3) break;;
      *) echo "无效选项";;
    esac
  done
}

# 主流程
install_environment
config_menu
staking_menu
