#!/bin/bash

set -e  # 有错就退出

# 默认 RPC
DEFAULT_RPC="https://base.meowrpc.com"
RPC_URL="$DEFAULT_RPC"
PRIVATE_KEY=""
ENV_FILE=".env.base"

# 1️⃣ 安装环境
function install_environment() {
  echo "🧱 正在安装开发环境..."

  echo "➡️ 安装 Rust..."
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
  source "$HOME/.cargo/env"

  echo "➡️ 安装 Risc0..."
  curl -L https://risczero.com/install | bash

  # 判断 shell 并设置配置文件
  SHELL_NAME=$(basename "$SHELL")
  RC_FILE=""
  if [ "$SHELL_NAME" = "zsh" ]; then
    RC_FILE="$HOME/.zshrc"
  elif [ "$SHELL_NAME" = "bash" ]; then
    RC_FILE="$HOME/.bashrc"
  else
    echo "⚠️ 无法识别 shell，请手动添加 Risc0 路径到 PATH"
  fi

  # 添加 ~/.risc0/bin 到 PATH
  export PATH="$HOME/.risc0/bin:$PATH"
  if [ -n "$RC_FILE" ] && ! grep -q 'risc0/bin' "$RC_FILE"; then
    echo 'export PATH="$HOME/.risc0/bin:$PATH"' >> "$RC_FILE"
    source "$RC_FILE"
  fi

  echo "➡️ 安装 Risc0 Rust toolchain..."
  rzup install
  rzup install rust

  echo "➡️ 安装 bento-cli..."
  cargo install --git https://github.com/risc0/risc0 bento-client --bin bento_cli

  export PATH="$HOME/.cargo/bin:$PATH"
  if [ -n "$RC_FILE" ] && ! grep -q 'cargo/bin' "$RC_FILE"; then
    echo 'export PATH="$HOME/.cargo/bin:$PATH"' >> "$RC_FILE"
    source "$RC_FILE"
  fi

  echo "➡️ 安装 boundless-cli..."
  cargo install --locked boundless-cli --force

  echo "✅ 环境安装完成！"
}

# 2️⃣ RPC 测试函数
function test_rpc() {
  echo "⏳ 正在测试 RPC 是否可用..."
  RESPONSE=$(curl -s -X POST "$RPC_URL" \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}')
  if [[ "$RESPONSE" != *"result"* ]]; then
    echo "❌ 无法连接到该 RPC，请检查网络或地址。"
    return 1
  else
    echo "✅ RPC 测试通过，链 ID：$(echo "$RESPONSE" | grep -o '"result":"[^"]*"' | cut -d':' -f2)"
    return 0
  fi
}

# 3️⃣ 写入 .env 文件
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

# 4️⃣ 配置菜单
function config_menu() {
  while true; do
    echo
    echo "📌 当前配置："
    echo "- RPC 地址：$RPC_URL"
    echo "- 私钥：$( [ -z "$PRIVATE_KEY" ] && echo '未设置 ❌' || echo '已设置 ✅' )"

    echo
    echo "🛠 配置选项："
    echo "1 - 修改 RPC"
    echo "2 - 修改私钥"
    echo "3 - 测试 RPC 并保存配置"
    echo "4 - 开始质押"
    echo "5 - 退出脚本"
    read -p "请输入选项编号: " CONFIG_CHOICE

    case "$CONFIG_CHOICE" in
      1)
        read -p "🔁 请输入新的 RPC 地址（当前：$RPC_URL）: " INPUT_RPC
        [ -n "$INPUT_RPC" ] && RPC_URL="$INPUT_RPC"
        ;;
      2)
        read -s -p "🔐 请输入你的私钥（不会显示）: " INPUT_KEY
        echo
        [ -n "$INPUT_KEY" ] && PRIVATE_KEY="$INPUT_KEY"
        ;;
      3)
        if test_rpc; then
          write_env_file
          echo "✅ 配置已保存到 .env.base"
        fi
        ;;
      4)
        if [ -z "$PRIVATE_KEY" ]; then
          echo "❌ 私钥未设置，请先设置私钥。"
        elif ! test_rpc; then
          echo "❌ RPC 不可用，请检查或更换地址。"
        else
          write_env_file
          break
        fi
        ;;
      5)
        echo "👋 已退出脚本"
        exit 0
        ;;
      *)
        echo "❌ 无效输入，请重新选择。"
        ;;
    esac
  done
}

# 5️⃣ 质押菜单
function staking_menu() {
  source "$ENV_FILE"
  while true; do
    echo
    echo "💎 请选择你要进行的操作："
    echo "1 - 质押 USDC"
    echo "2 - 质押 ETH"
    echo "3 - 退出脚本"
    read -p "请输入选项编号（1、2 或 3）: " STAKE_OPTION

    case "$STAKE_OPTION" in
      1)
        read -p "💰 输入 USDC 质押数量（例如 0.01）: " AMOUNT
        [ -z "$AMOUNT" ] && echo "❌ 金额不能为空。" && continue
        echo "🚀 正在质押 USDC..."
        boundless \
          --rpc-url "$ETH_RPC_URL" \
          --boundless-market-address "$BOUNDLESS_MARKET_ADDRESS" \
          --set-verifier-address "$SET_VERIFIER_ADDRESS" \
          --private-key "$PRIVATE_KEY" \
          --verifier-router-address "$VERIFIER_ADDRESS" \
          --order-stream-url "$ORDER_STREAM_URL" \
          account deposit-stake "$AMOUNT"
        echo "✅ USDC 质押成功！"
        ;;
      2)
        read -p "💰 输入 ETH 质押数量（例如 0.00001）: " AMOUNT
        [ -z "$AMOUNT" ] && echo "❌ 金额不能为空。" && continue
        echo "🚀 正在质押 ETH..."
        boundless \
          --rpc-url "$ETH_RPC_URL" \
          --boundless-market-address "$BOUNDLESS_MARKET_ADDRESS" \
          --set-verifier-address "$SET_VERIFIER_ADDRESS" \
          --private-key "$PRIVATE_KEY" \
          --verifier-router-address "$VERIFIER_ADDRESS" \
          --order-stream-url "$ORDER_STREAM_URL" \
          account deposit "$AMOUNT"
        echo "✅ ETH 质押成功！"
        ;;
      3)
        echo "👋 脚本结束，感谢使用！"
        break
        ;;
      *)
        echo "❌ 无效选项，请重新选择。"
        ;;
    esac
  done
}

# 🚀 主流程
install_environment
config_menu
staking_menu

