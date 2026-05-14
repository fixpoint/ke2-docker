#! /bin/sh
#
# init-env.sh
#
# ke2-docker の .env ファイルを生成するオプショナルなセットアップスクリプト。
#
# 用途:
#   compose の既定値 (kompira/guest) より強度の高いパスワードを簡単に
#   設定したい場合に使用する。.env には DATABASE_PASSWORD / AMQP_PASSWORD
#   のリテラル値と、URL エンコード済みの DATABASE_URL / AMQP_URL を
#   両方書き出すため、特殊文字を含むパスワードでも動作する。
#
# 任意ステップ:
#   このスクリプトの実行は任意。実行せずに直接 docker compose up しても
#   従来通り既定値 (kompira/guest) で動作する。
#
# Usage:
#   cd ke2/single/basic     # or ke2/single/extdb
#   ../../../scripts/init-env.sh [OPTIONS]
#
# Options:
#   --force                    既存の .env を上書きする
#   --db-user '<literal>'      DB ユーザ名を指定 (デフォルト: kompira)
#   --db-password '<literal>'  DB パスワードを指定 (未指定時はランダム生成)
#   --db-name '<literal>'      DB 名を指定 (デフォルト: kompira)
#   --mq-user '<literal>'      RabbitMQ ユーザ名を指定 (デフォルト: guest)
#   --mq-password '<literal>'  RabbitMQ パスワードを指定 (未指定時はランダム生成)
#   --database-url '<url>'     (extdb 専用) 外部 DB の URL。extdb では必須
#   --config <name>            構成を明示指定 (未指定時はカレントディレクトリから自動判定)
#                              指定可能な値: single/basic, single/extdb
#   --help                     ヘルプを表示
#
# Supported configurations (パス末尾 2 階層で識別):
#   - single/basic : 完全サポート (パスワードを生成または指定、URL は自動構成)
#   - single/extdb : AMQP 側のみ自動生成。DATABASE_URL は --database-url で必須指定
#
# Not supported (実行するとエラーで終了):
#   - cluster/swarm  : setup_stack.sh を利用 (本スクリプトの対象外)
#   - cloud/azureci  : ARM テンプレートで資格情報を管理
#   - extra/jobmngrd : 外部接続専用 (.env 生成は不要)
#
# 動作要件:
#   - POSIX 互換 shell (/bin/sh)
#   - 同ディレクトリに url-encode.sh が存在すること
#   - パスワード未指定時は openssl コマンド または /dev/urandom が必要
#
set -eu

# POSIX 互換のスクリプトディレクトリ検出 (readlink -f は GNU 拡張なので避ける)。
# シンボリックリンク経由の起動は想定しないため、cd + pwd で十分。
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
URL_ENCODE="$SCRIPT_DIR/url-encode.sh"

print_help() {
    sed -n '3,/^set -eu/{/^set -eu/d;s/^# \{0,1\}//;s/^#$//;p;}' "$0"
}

# --- argument parsing ---
FORCE=0
DB_USER=kompira
DB_PASSWORD=
DB_NAME=kompira
MQ_USER=guest
MQ_PASSWORD=
DATABASE_URL_ARG=
CONFIG=

# set -eu 下では `$2` 直接参照だと値省略時に "unbound variable" となり原因が
# 分かりにくいため、値付きオプションでは require_value で明示的に検査する。
require_value() {
    # $1: option name, $2: number of remaining args (= "$#")
    if [ "$2" -lt 2 ]; then
        echo "ERROR: option $1 requires a value" >&2
        exit 1
    fi
}

while [ $# -gt 0 ]; do
    case "$1" in
        --force)         FORCE=1 ;;
        --db-user)       require_value "$1" "$#"; DB_USER=$2; shift ;;
        --db-password)   require_value "$1" "$#"; DB_PASSWORD=$2; shift ;;
        --db-name)       require_value "$1" "$#"; DB_NAME=$2; shift ;;
        --mq-user)       require_value "$1" "$#"; MQ_USER=$2; shift ;;
        --mq-password)   require_value "$1" "$#"; MQ_PASSWORD=$2; shift ;;
        --database-url)  require_value "$1" "$#"; DATABASE_URL_ARG=$2; shift ;;
        --config)        require_value "$1" "$#"; CONFIG=$2; shift ;;
        --help|-h)       print_help; exit 0 ;;
        *) echo "ERROR: unknown option: $1" >&2; echo "Use --help for usage." >&2; exit 1 ;;
    esac
    shift
done

# --- prerequisite checks ---
if [ ! -x "$URL_ENCODE" ]; then
    echo "ERROR: url-encode.sh not found or not executable at $URL_ENCODE" >&2
    exit 1
fi

# --- detect configuration ---
# 末尾 2 階層 (例: "single/basic", "cluster/swarm") を識別キーに使う。
# basename だけだと将来 "cluster/basic" 等が追加されたときに区別できないため。
if [ -z "$CONFIG" ]; then
    parent_base=$(basename "$(dirname "$PWD")")
    cwd_base=$(basename "$PWD")
    cwd_key="$parent_base/$cwd_base"
    case "$cwd_key" in
        single/basic)
            CONFIG=single/basic ;;
        single/extdb)
            CONFIG=single/extdb ;;
        cluster/swarm)
            echo "ERROR: cluster/swarm is not supported by this script." >&2
            echo "  Use setup_stack.sh for Swarm cluster setup. See:" >&2
            echo "  https://fixpoint.github.io/ke2-admin-manual/setup/cluster/swarm/" >&2
            exit 1 ;;
        cloud/azureci)
            echo "ERROR: cloud/azureci is not supported by this script." >&2
            echo "  Credentials are managed via ARM template parameters." >&2
            exit 1 ;;
        extra/jobmngrd)
            echo "ERROR: extra/jobmngrd is not supported by this script." >&2
            echo "  Set AMQP_URL directly when running docker compose up." >&2
            exit 1 ;;
        *)
            echo "ERROR: cannot detect configuration from current directory ($PWD)." >&2
            echo "  Detected path key: '$cwd_key' (expected: single/basic or single/extdb)." >&2
            echo "  Run this script from ke2/single/basic or ke2/single/extdb." >&2
            echo "  Or specify explicitly with --config single/basic or --config single/extdb." >&2
            exit 1 ;;
    esac
fi

case "$CONFIG" in
    single/basic|single/extdb) ;;
    *) echo "ERROR: unsupported config: $CONFIG (supported: single/basic, single/extdb)" >&2; exit 1 ;;
esac

# --- check existing .env ---
if [ -f .env ] && [ $FORCE -eq 0 ]; then
    echo "ERROR: .env already exists in $PWD" >&2
    echo "  Use --force to overwrite." >&2
    exit 1
fi

# --- extdb-specific: require --database-url ---
if [ "$CONFIG" = single/extdb ] && [ -z "$DATABASE_URL_ARG" ]; then
    echo "ERROR: extdb configuration requires --database-url '<url>'" >&2
    echo "  The external DB URL must be specified explicitly." >&2
    echo "  Example:" >&2
    echo "    --database-url 'pgsql://kompira:\$(../../../scripts/url-encode.sh PASSWORD)@10.20.0.10:5432/kompira'" >&2
    exit 1
fi

# --- random password generator (POSIX) ---
random_password() {
    if command -v openssl >/dev/null 2>&1; then
        openssl rand -hex 16
    elif [ -r /dev/urandom ]; then
        head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n'
    else
        echo "ERROR: cannot generate random password" >&2
        echo "  Neither 'openssl' command nor /dev/urandom is available." >&2
        echo "  Specify passwords explicitly with --db-password and --mq-password." >&2
        exit 1
    fi
}

# --- generate or use provided passwords ---
# 利用者がリテラル指定したパスワードに URL 予約文字を含む場合、kompira-v2 側の
# 修正 (Issue #367, v2.0.5.post2 以降のコンテナイメージで提供) が必要となる
# ため、利用者が気付けるよう警告を出力する (継続実行は妨げない)。
url_unsafe_warning() {
    var_name="$1"
    value="$2"
    case "$value" in
        *[!A-Za-z0-9._~-]*)
            echo "WARNING: $var_name contains URL-reserved characters." >&2
            echo "  $var_name の URL 予約文字を正しく扱うには、kompira コンテナイメージが" >&2
            echo "  Issue #367 修正版 (v2.0.5.post2 以降) である必要があります。" >&2
            echo "  v2.0.5.post1 以前のイメージを利用する場合は、$var_name に" >&2
            echo "  英数字と '-_.~' のみを使用してください。" >&2
            ;;
    esac
}

# DATABASE_PASSWORD は django-environ の env.db_url() が unquote するため
# 特殊文字を含めても kompira-v2 のバージョンに依存せず動作する。よって
# url_unsafe_warning は呼ばない (AMQP_PASSWORD 側のみ警告対象)。
[ -z "$DB_PASSWORD" ] && DB_PASSWORD=$(random_password)

if [ -n "$MQ_PASSWORD" ]; then
    url_unsafe_warning AMQP_PASSWORD "$MQ_PASSWORD"
else
    MQ_PASSWORD=$(random_password)
fi

# --- URL-encode user / password fields for URL embedding ---
# ユーザ名側にも特殊文字が含まれうるため、念のため両方をエンコードする。
DB_USER_ENC=$("$URL_ENCODE" "$DB_USER")
DB_PASSWORD_ENC=$("$URL_ENCODE" "$DB_PASSWORD")
MQ_USER_ENC=$("$URL_ENCODE" "$MQ_USER")
MQ_PASSWORD_ENC=$("$URL_ENCODE" "$MQ_PASSWORD")

# --- generate .env ---
TIMESTAMP=$(date '+%Y-%m-%dT%H:%M:%S%z')

# 新規作成の .env が world-readable にならないよう umask を絞る (新規作成のみ有効)
umask 077

{
    # ヘッダ (共通)
    echo "# Generated by ke2-docker init-env.sh at $TIMESTAMP"
    echo "# Configuration: $CONFIG"
    echo ""

    # データベース関連 (CONFIG により差分あり)
    case "$CONFIG" in
        single/basic)
            cat <<EOF
# DATABASE_USER / DATABASE_PASSWORD / DATABASE_NAME:
#   literal values used by the internal postgres container for initial setup.
# DATABASE_URL:
#   connection URL with the same values, user/password URL-encoded for django.
DATABASE_USER=$DB_USER
DATABASE_PASSWORD=$DB_PASSWORD
DATABASE_NAME=$DB_NAME
DATABASE_URL=pgsql://$DB_USER_ENC:$DB_PASSWORD_ENC@postgres:5432/$DB_NAME
EOF
            ;;
        single/extdb)
            cat <<EOF
# DATABASE_URL: external DB URL (provided via --database-url).
#               Its embedded password must already be URL-encoded by the user.
DATABASE_URL=$DATABASE_URL_ARG
EOF
            ;;
    esac

    echo ""

    # AMQP 関連 (共通)
    cat <<EOF
# AMQP_USER / AMQP_PASSWORD:
#   literal values used by the internal rabbitmq container for initial setup.
# AMQP_URL:
#   connection URL with the same values, user/password URL-encoded for clients.
AMQP_USER=$MQ_USER
AMQP_PASSWORD=$MQ_PASSWORD
AMQP_URL=amqp://$MQ_USER_ENC:$MQ_PASSWORD_ENC@rabbitmq:5672
EOF
} > .env

# --force で既存ファイルを上書きしたケースでは umask が効かないので、
# 書き込み後に明示的にパーミッションを 600 に揃える。
chmod 600 .env

echo "Generated $PWD/.env (permissions: 600)"
echo "Run 'docker compose up -d' to start ke2."
