#!/bin/bash

# --- 設定ファイル ---
CONFIG_FILE="api/config/embedder.json"
ENV_FILE=".env"
COMPOSE_FILE="docker-compose.yml"
ADALFLOW_DIR="~/.adalflow"

# --- 色付け (お姉さん風) ---
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# --- 関数: embedder.json を API モードに設定 ---
set_api_mode() {
  echo -e "${CYAN} embedder.json を API モード (OpenAI/Gemini) に設定するね...${NC}"
  # "embedder" (デフォルト) を OpenAI に、"embedder_ollama" を Ollama に設定する
  cat > "$CONFIG_FILE" << EOF
{
  "embedder": {
    "client_class": "OpenAIClient",
    "model_kwargs": {
      "model": "text-embedding-3-small"
    }
  },
  "embedder_ollama": {
    "client_class": "OllamaClient",
    "model_kwargs": {
      "model": "nomic-embed-text"
    }
  },
  "retriever": {
    "top_k": 20
  },
  "text_splitter": {
    "split_by": "word",
    "chunk_size": 350,
    "chunk_overlap": 100
  }
}
EOF
}

# --- 関数: embedder.json を Ollama モードに設定 ---
set_ollama_mode() {
  echo -e "${CYAN} embedder.json を Ollama ローカルモードに設定するよ...${NC}"
  # バグ回避のため、"embedder" と "embedder_ollama" の両方を Ollama に設定する
  cat > "$CONFIG_FILE" << EOF
{
  "embedder": {
    "client_class": "OllamaClient",
    "model_kwargs": {
      "model": "nomic-embed-text"
    }
  },
  "embedder_ollama": {
    "client_class": "OllamaClient",
    "model_kwargs": {
      "model": "nomic-embed-text"
    }
  },
  "retriever": {
    "top_k": 20
  },
  "text_splitter": {
    "split_by": "word",
    "chunk_size": 350,
    "chunk_overlap": 100
  }
}
EOF
}

# --- メインスクリプト ---
clear
echo -e "${CYAN} DeepWiki のセットアップを始めるよ。${NC}"
echo "-----------------------------------------------------"
echo ""

# 1. 重みファイルの移行確認
echo -e "${YELLOW}ステップ 1: 解析結果（重みファイル）の移行${NC}"
echo "別の PC で解析した結果（${ADALFLOW_DIR} フォルダ）を持ってる？"
echo -n "持ってるなら 'y' を押してね (y/n): "
read -r migrate_choice

if [[ "$migrate_choice" == "y" || "$migrate_choice" == "Y" ]]; then
  echo ""
  echo -e "${GREEN}--- 重みファイルの移行手順 ---${NC}"
  echo "1. 解析済みの PC から ${ADALFLOW_DIR} フォルダを丸ごとコピーして、"
  echo "   この PC のホームディレクトリ (${HOME}) に置いてね。"
  echo "   (中身: ${ADALFLOW_DIR}/databases/ と ${ADALFLOW_DIR}/wikicache/)"
  echo ""
  echo -e "${YELLOW}※リポジトリ本体のパスは、この後のステップで設定するから、ここでは ${ADALFLOW_DIR} のコピーだけ気にすればいいよ。${NC}"
  echo ""
  echo -n "準備ができたら、Enter を押して次に進んでね..."
  read -r
else
  echo ""
  echo -e "${CYAN}OK。じゃあ、この PC で新しく解析するね。${NC}"
  echo ""
fi

# 2. Embedder の選択
echo "-----------------------------------------------------"
echo -e "${YELLOW}ステップ 2: Embedder (埋め込み) の設定${NC}"
echo "どっちの embedder を使う？"
echo ""
echo "  1) ${GREEN}Gemini / OpenAI API${NC} (ネットワーク越し。こっちを選ぶなら API キーが必要だよ)"
echo "  2) ${CYAN}Ollama${NC} (ローカル PC (RTX5060ti とか) で動かす用)"
echo ""
echo -n "番号を選んでね (1 or 2): "
read -r embedder_choice

# 3. .env ファイルの設定
echo "-----------------------------------------------------"
echo -e "${YELLOW}ステップ 3: .env ファイルの設定${NC}"

if [[ "$embedder_choice" == "1" ]]; then
  # API モード
  set_api_mode
  
  echo "API モードだね。 .env ファイルに API キーを書き込むよ。"
  echo -e "${YELLOW}Google API キー (Gemini 用) を入力してね:${NC} (入力は隠れるよ)"
  read -s GOOGLE_KEY
  echo ""
  echo -e "${YELLOW}OpenAI API キー (Embedder 用) を入力してね:${NC} (入力は隠れるよ)"
  read -s OPENAI_KEY
  
  # .env ファイルに書き込む
  cat > "$ENV_FILE" << EOF
# API キー
GOOGLE_API_KEY=${GOOGLE_KEY}
OPENAI_API_KEY=${OPENAI_KEY}
EOF
  
  echo ""
  echo -e "${GREEN}OK。 .env ファイルにキーを書き込んだよ。${NC}"

else
  # Ollama モード (デフォルト)
  set_ollama_mode
  
  # Ollama モードでも起動チェックを通すためにダミーキーが必要
  cat > "$ENV_FILE" << EOF
# Ollama モード用: 起動チェックを通過するためのダミーキー
OPENAI_API_KEY=DUMMY_KEY_TO_PASS_CHECK
EOF
  
  echo "Ollama モードだね。 .env ファイルにはダミーキーを設定したよ。"
fi
echo ""

# 4. ローカルリポジトリのマウント設定 (★ここから追加★)
echo "-----------------------------------------------------"
echo -e "${YELLOW}ステップ 4: ローカルリポジトリのマウント${NC}"
echo "コンテナにマウントしたい（解析したい）ローカルリポジトリのパスを追加するよ。"
echo -e "（${YELLOW}${COMPOSE_FILE}${NC} を直接編集するから、気をつけてね）"
echo ""

while true; do
  echo -n "マウントする ${YELLOW}ホスト側${NC} のパスを入力してね (例: /home/guch1/ssd_yamaguchi/HSR): "
  read -r HOST_PATH
  
  # パスが空だったらループを抜ける
  if [ -z "$HOST_PATH" ]; then
    echo -e "${CYAN}パスが入力されなかったから、マウント設定は終わりにするね。${NC}"
    break
  fi
  
  echo -n "マウントする ${YELLOW}コンテナ側${NC} のパスを入力してね (例: /app/HSR): "
  read -r CONTAINER_PATH

  if [ -z "$CONTAINER_PATH" ]; then
    echo -e "${RED}コンテナ側のパスは空にできないよ。もう一回やり直して。${NC}"
    continue
  fi

  # docker-compose.yml があるか確認
  if [ ! -f "$COMPOSE_FILE" ]; then
      echo -e "${RED}エラー: ${COMPOSE_FILE} が見つからないよ。${NC}"
      exit 1
  fi

  # healthcheck の行の直前に、新しい volume マウントを追加する (sed -i を使用)
  # インデントはスペース 6 個
  sed -i "/^ *healthcheck:/i \      - ${HOST_PATH}:${CONTAINER_PATH} # Added by script" "$COMPOSE_FILE"

  if [ $? -eq 0 ]; then
      echo -e "${GREEN}OK。 ${COMPOSE_FILE} に '${HOST_PATH}:${CONTAINER_PATH}' を追加したよ。${NC}"
  else
      echo -e "${RED}あ... ${COMPOSE_FILE} の編集に失敗したみたい。${NC}"
      echo "ファイルが書き込み可能か確認してみて。"
      exit 1
  fi
  
  echo ""
  echo -n "ほかにもリポジトリを追加する？ (y/n): "
  read -r add_more
  if [[ "$add_more" != "y" && "$add_more" != "Y" ]]; then
    break
  fi
  echo ""
done
# (★ここまで追加★)


# 5. コンテナ実行
echo ""
echo "-----------------------------------------------------"
echo -e "${YELLOW}ステップ 5: コンテナの起動${NC}"
echo "設定は全部終わったよ。"
echo "今からコンテナを ${GREEN}リビルド (build)${NC} して ${GREEN}起動 (up)${NC} するね。"
echo "（もし Docker イメージが最新なら、ビルドはすぐ終わるよ）"
echo ""
echo "ログが流れ始めるから止めないで、気長に待ってあげてね..."
echo "-----------------------------------------------------"
sleep 3 # ちょっと待つ

# Docker Compose を実行 (-d でバックグラウンド起動)
docker compose up --build -d

# ログを表示
if [ $? -eq 0 ]; then
    echo ""
    echo -e "${GREEN}コンテナが起動したよ。ログを表示するね...${NC}"
    echo "（止めたいときは Ctrl+C を押してね）"
    echo ""
    docker compose logs -f deepwiki-1
else
    echo -e "${RED}あ... コンテナの起動に失敗したみたい。${NC}"
    echo "ログを確認してみて。"
fi

exit 0