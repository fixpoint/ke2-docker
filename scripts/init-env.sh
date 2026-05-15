#! /bin/sh
#
# init-env.sh
#
# ke2-docker の .env ファイルを生成するオプショナルなセットアップスクリプト。
#
# 用途:
#   compose の既定値 (kompira/guest) より強度の高いパスワードを簡単に
#   設定したい場合に使用する。
#   - single/basic: .env に DATABASE_USER / DATABASE_PASSWORD / DATABASE_NAME /
#     AMQP_USER / AMQP_PASSWORD のリテラル値と、URL エンコード済みの
#     DATABASE_URL / AMQP_URL の両方を書き出すため、特殊文字を含む値でも動作する。
#   - single/extdb: 利用者が --database-url で渡した URL をそのまま .env に
#     書き出し、AMQP_USER / AMQP_PASSWORD のリテラル値と URL エンコード済みの
#     AMQP_URL を併せて書き出す (DB 側のユーザ名・パスワード・DB 名は URL に
#     利用者責任で URL エンコード済みで含めてもらう想定)。
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
#   - POSIX 互換 shell (/bin/sh) と POSIX 標準ユーティリティ群
#     (sed / od / tr / dd / date / chmod / printf など)
#   - 同ディレクトリに url-encode.sh が存在すること
#   - パスワード未指定時は openssl コマンド または /dev/urandom が必要
#
set -eu

# url_unsafe_warning 等で使う文字クラス (`[A-Za-z0-9._~-]`) は POSIX shell の
# 文字クラスとして locale 依存に解釈され、非 `C` locale では非 ASCII 文字が
# 「unreserved」と誤判定されることがある。安定動作のため LC_ALL=C を強制し、
# ASCII 範囲で確実に判定する (date / sed / printf 等の出力にも波及するが、
# 本スクリプトで使う出力はすべて ASCII 範囲なので副作用はない)。
LC_ALL=C
export LC_ALL

# POSIX 互換のスクリプトディレクトリ検出 (readlink -f は GNU 拡張なので避ける)。
# シンボリックリンク経由の起動は想定しないため、cd + pwd で十分。
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
URL_ENCODE="$SCRIPT_DIR/url-encode.sh"

# set -u 下では未設定変数の参照でスクリプトが落ちる。
# 通常 $PWD は shell が自動設定するが、unset/絞り込み環境を想定して
# pwd の結果を CWD に明示的に取得しておき、以降は $CWD を使う。
CWD=$(pwd)

# 利用者が独自に追記した環境変数定義を再実行時に保持するためのマーカー行。
# awk の完全一致 (`$0 == MARKER_LINE`) で検出するため、他のコメント行と
# 識別しやすいよう記号・大文字・アンダースコアのみで構成し、途中の空白は
# 含めない (`#` 直後の 1 空白だけは通常コメント表記との統一感のため許容)。
MARKER_LINE="# =====KE2_DOCKER_INIT_ENV_END====="

print_help() {
    sed -n '3,/^set -eu/{/^set -eu/d;s/^# \{0,1\}//;s/^#$//;p;}' "$0"
}

# --- argument parsing ---
# *_SET フラグは「利用者が値付きオプションを明示指定したか」を区別するために
# 使う (random_password() 呼び出し判定や single/extdb の整合性検査で必要)。
# 空文字列 (`--xxx ""`) は後段の require_nonempty で事前に reject されるため、
# *_SET=1 のときは必ず非空値が入る前提で扱える。
FORCE=0
DB_USER=kompira
DB_USER_SET=0
DB_PASSWORD=
DB_PASSWORD_SET=0
DB_NAME=kompira
DB_NAME_SET=0
MQ_USER=guest
MQ_PASSWORD=
MQ_PASSWORD_SET=0
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

# 値付きオプションに空文字列を渡すと、後段で .env に空値が書き出され、
# 内部 postgres / rabbitmq コンテナの初期化や DATABASE_URL の組み立てが
# 破綻する (postgres は POSTGRES_PASSWORD="" で起動拒否、rabbitmq は
# 初期ユーザの認証が成立しない等)。意図しない空文字指定を防ぐため、
# 値付きオプションでは require_nonempty で空文字を明示的に reject する。
require_nonempty() {
    # $1: option name, $2: given value
    if [ -z "$2" ]; then
        echo "ERROR: option $1 requires a non-empty value" >&2
        exit 1
    fi
}

while [ $# -gt 0 ]; do
    case "$1" in
        --force)         FORCE=1 ;;
        --db-user)       require_value "$1" "$#"; require_nonempty "$1" "$2"; DB_USER=$2; DB_USER_SET=1; shift ;;
        --db-password)   require_value "$1" "$#"; require_nonempty "$1" "$2"; DB_PASSWORD=$2; DB_PASSWORD_SET=1; shift ;;
        --db-name)       require_value "$1" "$#"; require_nonempty "$1" "$2"; DB_NAME=$2; DB_NAME_SET=1; shift ;;
        --mq-user)       require_value "$1" "$#"; require_nonempty "$1" "$2"; MQ_USER=$2; shift ;;
        --mq-password)   require_value "$1" "$#"; require_nonempty "$1" "$2"; MQ_PASSWORD=$2; MQ_PASSWORD_SET=1; shift ;;
        --database-url)  require_value "$1" "$#"; require_nonempty "$1" "$2"; DATABASE_URL_ARG=$2; shift ;;
        --config)        require_value "$1" "$#"; require_nonempty "$1" "$2"; CONFIG=$2; shift ;;
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
# .env はカレントディレクトリに生成されるため、cwd_key は --config 指定の
# 有無に関わらず必ず検査する (誤った場所への .env 生成や明示的に非対象と
# している構成 (cluster/swarm 等) からの実行を防ぐ目的)。
parent_base=$(basename "$(dirname "$CWD")")
cwd_base=$(basename "$CWD")
cwd_key="$parent_base/$cwd_base"
case "$cwd_key" in
    single/basic|single/extdb)
        ;;
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
        echo "ERROR: cannot detect configuration from current directory ($CWD)." >&2
        echo "  Detected path key: '$cwd_key' (expected: single/basic or single/extdb)." >&2
        echo "  Run this script from ke2/single/basic or ke2/single/extdb." >&2
        exit 1 ;;
esac

# --config 未指定なら cwd_key を採用、指定済みなら cwd_key との一致を検査する。
# (--config だけでカレントディレクトリ検査をスキップすると、利用者が誤った場所で
# .env を生成してしまう恐れがあるため。)
if [ -z "$CONFIG" ]; then
    CONFIG=$cwd_key
elif [ "$CONFIG" != "$cwd_key" ]; then
    echo "ERROR: --config '$CONFIG' does not match current directory ($cwd_key)." >&2
    echo "  Either move to the matching directory or drop --config." >&2
    exit 1
fi

case "$CONFIG" in
    single/basic|single/extdb) ;;
    *) echo "ERROR: unsupported config: $CONFIG (supported: single/basic, single/extdb)" >&2; exit 1 ;;
esac

# --- option / config 整合性検証 ---
# 構成と関係ないオプションを指定した場合は明示的にエラーにする
# (silent ignore だと利用者が「効いた」と勘違いするため)。
case "$CONFIG" in
    single/basic)
        if [ -n "$DATABASE_URL_ARG" ]; then
            echo "ERROR: --database-url is only valid for single/extdb config." >&2
            echo "  In single/basic, DATABASE_URL is auto-constructed from" >&2
            echo "  --db-user / --db-password / --db-name (defaults: kompira)." >&2
            exit 1
        fi
        ;;
    single/extdb)
        # extdb では DB ユーザ・パスワード・DB 名は --database-url の中に
        # URL エンコード済みで埋め込む形式のため、個別の --db-* オプションは
        # 意味を持たない。
        if [ "$DB_USER_SET" = 1 ] || [ "$DB_PASSWORD_SET" = 1 ] || [ "$DB_NAME_SET" = 1 ]; then
            echo "ERROR: --db-user / --db-password / --db-name are not used in single/extdb config." >&2
            echo "  Include the DB user/password/name (URL-encoded) inside --database-url instead." >&2
            exit 1
        fi
        ;;
esac

# --- check existing .env ---
if [ -f .env ] && [ $FORCE -eq 0 ]; then
    echo "ERROR: .env already exists in $CWD" >&2
    echo "  Use --force to overwrite." >&2
    exit 1
fi

# --force で上書きする場合は以下を実施:
#   (1) 既存 .env をタイムスタンプ付きでバックアップ
#   (2) 既存 .env にマーカー行があれば、マーカー以降の独自追記分を
#       退避して新しい .env に結合する (再実行で独自設定が消えないように)
#   (3) マーカー行がない (旧版 or 手書きの .env など) 場合は warning を出力。
#       独自設定があった場合はバックアップから手動転記する必要あり。
USER_CUSTOM=""
if [ -f .env ] && [ "$FORCE" -eq 1 ]; then
    BACKUP=".env.bak.$(date '+%Y%m%d-%H%M%S')"
    cp -p .env "$BACKUP"
    # cp -p は元 .env の mode を引き継ぐが、元が緩いパーミッションだった
    # 場合にバックアップにもパスワード等の credentials が残るのは危険。
    # バックアップは常に 600 に切り詰める。
    chmod 600 "$BACKUP"
    echo "Backed up existing .env to $BACKUP (permissions: 600)"

    if grep -qFx "$MARKER_LINE" .env; then
        # マーカー行の次の行から末尾までを退避。`$(...)` は末尾改行を
        # 削除するためダミー終端文字 _ で保持し、最後に ${...%_} で取り除く。
        USER_CUSTOM=$(awk -v m="$MARKER_LINE" 'f { print } $0 == m { f = 1 }' .env; printf '_')
        USER_CUSTOM=${USER_CUSTOM%_}
    else
        echo "WARNING: existing .env has no marker line; any custom additions" >&2
        echo "  will NOT be carried over to the regenerated .env." >&2
        echo "  Recover from $BACKUP if needed." >&2
    fi
fi

# --- extdb-specific: require --database-url ---
if [ "$CONFIG" = single/extdb ] && [ -z "$DATABASE_URL_ARG" ]; then
    echo "ERROR: extdb configuration requires --database-url '<url>'" >&2
    echo "  The external DB URL must be specified explicitly. The embedded password" >&2
    echo "  must already be URL-encoded (RFC 3986)." >&2
    echo "  Example 1: pre-encoded password (single quotes are safe to copy)" >&2
    echo "    --database-url 'pgsql://kompira:p%40ss%3Aw0rd@10.20.0.10:5432/kompira'" >&2
    echo "  Example 2: encode with url-encode.sh first, then substitute" >&2
    echo "    ENC=\$(../../../scripts/url-encode.sh '<raw password>')" >&2
    echo "    --database-url \"pgsql://kompira:\$ENC@10.20.0.10:5432/kompira\"" >&2
    exit 1
fi

# --- random password generator (POSIX) ---
random_password() {
    if command -v openssl >/dev/null 2>&1; then
        openssl rand -hex 16
    elif [ -r /dev/urandom ]; then
        # head -c は POSIX 必須ではないため dd を使う (dd / od / tr は POSIX 必須)。
        # od のオプションは POSIX 形式 (-A n -t x1) で分けて書く (-An -tx1 は GNU 拡張)。
        dd if=/dev/urandom bs=16 count=1 2>/dev/null | od -A n -t x1 | tr -d ' \n'
    else
        echo "ERROR: cannot generate random password" >&2
        echo "  Neither 'openssl' command nor /dev/urandom is available." >&2
        echo "  Specify passwords explicitly with --db-password and --mq-password." >&2
        exit 1
    fi
}

# --- generate or use provided passwords ---
# 利用者がリテラル指定したパスワードに URL に安全でない文字 (RFC 3986
# unreserved set 以外: 予約文字 @ : / 等に加え、空白などの unsafe 文字も含む)
# が含まれる場合、kompira コンテナイメージは v2.0.5.post2 以降が必要となる
# ため、利用者が気付けるよう警告を出力する (継続実行は妨げない)。
url_unsafe_warning() {
    var_name="$1"
    value="$2"
    case "$value" in
        *[!A-Za-z0-9._~-]*)
            echo "WARNING: $var_name contains URL-unsafe characters (chars outside RFC 3986 unreserved set)." >&2
            echo "  To handle URL-unsafe characters in $var_name correctly," >&2
            echo "  kompira container image must be v2.0.5.post2 or later." >&2
            echo "  For older images (<=v2.0.5.post1), restrict $var_name to" >&2
            echo "  alphanumerics and '-_.~' only." >&2
            ;;
    esac
}

# AMQP_USER / AMQP_PASSWORD は basic / extdb いずれの構成でも .env に書き出す。
[ "$MQ_PASSWORD_SET" = 0 ] && MQ_PASSWORD=$(random_password)

# AMQP_URL の userinfo に埋め込む AMQP_USER / AMQP_PASSWORD は、受け取り側
# (kompira コンテナ) が URL デコードできる v2.0.5.post2 以降が必要なので、
# URL 安全でない文字を含む場合は両方を警告対象にする。
url_unsafe_warning AMQP_USER "$MQ_USER"
url_unsafe_warning AMQP_PASSWORD "$MQ_PASSWORD"

# 改行 (LF / CR) を含む値は .env が壊れる/追加エントリ注入の原因になるため拒否。
# dotenv_quote は \ と " しかエスケープしないので、改行は ${var} 行の終端と
# 解釈されてしまう。
# 注: $() は末尾改行を削除するため、ダミー終端文字 _ を付けてから ${...%_} で
# 取り除くことで改行/CR をリテラル値として保持する。
NL=$(printf '\n_'); NL=${NL%_}
CR=$(printf '\r_'); CR=${CR%_}
reject_newline() {
    var_name="$1"
    value="$2"
    case "$value" in
        *"$NL"*|*"$CR"*)
            echo "ERROR: $var_name contains newline or CR characters." >&2
            echo "  Newline/CR cannot be safely embedded in .env values." >&2
            exit 1
            ;;
    esac
}
reject_newline AMQP_USER     "$MQ_USER"
reject_newline AMQP_PASSWORD "$MQ_PASSWORD"

# --- dotenv value escaping ---
# Compose v2 の .env パーサ仕様: ダブルクオートで囲んだ値は中身の \ と "
# だけがエスケープシーケンスとして解釈される。リテラル値に空白・#・'・"
# などを含んでも .env パースが壊れないよう、全値を minimal エスケープして
# ダブルクオートで包む形に統一する。
dotenv_quote() {
    val=$(printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')
    printf '"%s"' "$val"
}

# AMQP は basic / extdb 共通で .env に書き出す
MQ_USER_ENC=$("$URL_ENCODE" "$MQ_USER")
MQ_PASSWORD_ENC=$("$URL_ENCODE" "$MQ_PASSWORD")
MQ_USER_DQ=$(dotenv_quote "$MQ_USER")
MQ_PASSWORD_DQ=$(dotenv_quote "$MQ_PASSWORD")
MQ_URL_DQ=$(dotenv_quote "amqp://$MQ_USER_ENC:$MQ_PASSWORD_ENC@rabbitmq:5672")

# DB 関連は構成ごとに分岐:
# - basic: 内部 postgres コンテナ用に DB_USER / DB_PASSWORD / DB_NAME を生成し
#   URL エンコード + dotenv_quote して .env に書き出す
# - extdb: DATABASE_URL_ARG をそのまま dotenv_quote して .env に書き出す
#   (DB ユーザ名・パスワードは URL に既に含まれているのでスクリプト側で
#   ランダム生成や URL エンコードは不要)
# なお AMQP 関連 (MQ_PASSWORD) は構成共通で扱い、--mq-password 未指定時は
# どちらの構成でも random_password() が呼ばれる。openssl / /dev/urandom の
# 双方が無い最小環境では --mq-password の明示指定が必要。
case "$CONFIG" in
    single/basic)
        # DATABASE_PASSWORD: 本スクリプトは DATABASE_URL を URL エンコード済みの形で
        # .env に出力するため、特殊文字を含むパスワードも DATABASE_URL 経由で正しく
        # 動作する (受け取り側の django-environ が unquote するため、kompira-v2 の
        # バージョンにも依存しない)。AMQP_PASSWORD と異なりバージョン依存の警告は
        # 不要なので url_unsafe_warning は呼ばない。
        [ "$DB_PASSWORD_SET" = 0 ] && DB_PASSWORD=$(random_password)
        reject_newline DATABASE_USER     "$DB_USER"
        reject_newline DATABASE_PASSWORD "$DB_PASSWORD"
        reject_newline DATABASE_NAME     "$DB_NAME"
        DB_USER_ENC=$("$URL_ENCODE" "$DB_USER")
        DB_PASSWORD_ENC=$("$URL_ENCODE" "$DB_PASSWORD")
        DB_NAME_ENC=$("$URL_ENCODE" "$DB_NAME")
        DB_USER_DQ=$(dotenv_quote "$DB_USER")
        DB_PASSWORD_DQ=$(dotenv_quote "$DB_PASSWORD")
        DB_NAME_DQ=$(dotenv_quote "$DB_NAME")
        DB_URL_DQ=$(dotenv_quote "pgsql://$DB_USER_ENC:$DB_PASSWORD_ENC@postgres:5432/$DB_NAME_ENC")
        ;;
    single/extdb)
        reject_newline DATABASE_URL "$DATABASE_URL_ARG"
        EXTDB_URL_DQ=$(dotenv_quote "$DATABASE_URL_ARG")
        ;;
esac

# --- generate .env ---
# `%z` (オフセット) や `-u` (UTC 強制) はいずれも POSIX 必須ではないため、
# ローカルタイム + タイムゾーン名 (`%Z` は POSIX 必須) の形式で出力する。
TIMESTAMP=$(date '+%Y-%m-%dT%H:%M:%S %Z')

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
DATABASE_USER=$DB_USER_DQ
DATABASE_PASSWORD=$DB_PASSWORD_DQ
DATABASE_NAME=$DB_NAME_DQ
DATABASE_URL=$DB_URL_DQ
EOF
            ;;
        single/extdb)
            cat <<EOF
# DATABASE_URL: external DB URL (provided via --database-url).
#               Its embedded password must already be URL-encoded by the user.
DATABASE_URL=$EXTDB_URL_DQ
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
AMQP_USER=$MQ_USER_DQ
AMQP_PASSWORD=$MQ_PASSWORD_DQ
AMQP_URL=$MQ_URL_DQ
EOF

    # 利用者向けの説明コメントとマーカー行。マーカー行は「init-env.sh の
    # 生成領域と利用者領域の境界」として機能し、再実行 (--force) 時には
    # マーカー以降の独自追記分を退避して新しい .env のマーカー直下に
    # 再結合する (説明コメントは毎回新規生成なので重複しない)。
    echo ""
    echo "# Add your custom environment variables below the marker line."
    echo "# Lines after the marker are preserved across init-env.sh --force re-runs."
    echo "# Re-defining DATABASE_URL / AMQP_URL etc. below will override the generated values above"
    echo "# (compose reads .env top-to-bottom, so later lines win)."
    echo "$MARKER_LINE"

    # 既存 .env から退避していた独自追記分があれば、マーカー直下に結合。
    if [ -n "$USER_CUSTOM" ]; then
        printf '%s' "$USER_CUSTOM"
    fi
} > .env

# --force で既存ファイルを上書きしたケースでは umask が効かないので、
# 書き込み後に明示的にパーミッションを 600 に揃える。
chmod 600 .env

echo "Generated $CWD/.env (permissions: 600)"
echo "Run 'docker compose up -d' to start ke2."
