#! /bin/sh
#
# url-encode.sh
#
# 任意の文字列を RFC 3986 unreserved set (英数字と "-_.~") 以外を
# パーセントエンコードした URL エンコード形式で標準出力に書き出す。
#
# DATABASE_URL / AMQP_URL に埋め込む文字列のエスケープに利用する。
# パスワードに限らず、ユーザ名・データベース名など URL に埋め込むあらゆる
# 文字列に使える汎用ヘルパー。
#
# Usage:
#   $ ./scripts/url-encode.sh '<string>'
#
# Examples:
#   $ ./scripts/url-encode.sh 'p@ss:w0rd'
#   p%40ss%3Aw0rd
#
#   $ ./scripts/url-encode.sh 'user@example.com'
#   user%40example.com
#
#   $ ./scripts/url-encode.sh 'db name with spaces'
#   db%20name%20with%20spaces
#
# 動作要件:
#   - POSIX 互換 shell (/bin/sh)
#   - 外部コマンド依存なし (printf のみ使用)
#
# 制限:
#   - ASCII 範囲の文字列を入力として想定。多バイト UTF-8 などの非 ASCII 入力
#     に対する挙動はシェル実装によって異なるため、ASCII の範囲で使用すること。
#   - 引数なしでは usage を表示して終了する。
#
set -eu

if [ $# -ne 1 ]; then
    echo "Usage: $0 '<string>'" >&2
    echo "  Outputs URL-encoded form of <string> on stdout." >&2
    echo "  Use single quotes to avoid shell expansion of special characters." >&2
    exit 1
fi

s="$1"
while [ -n "$s" ]; do
    # POSIX trick: extract the first character of $s without external commands.
    #   ${s#?}  = $s with the first character removed
    #   ${s%X}  = $s with X removed from the end
    # combine them to get the first character only.
    c=${s%"${s#?}"}
    case "$c" in
        [A-Za-z0-9._~-])
            printf '%s' "$c"
            ;;
        *)
            # The "'$c" form makes printf treat $c's first byte as a numeric
            # value (POSIX-defined behavior). 0xHH format gives uppercase hex.
            printf '%%%02X' "'$c"
            ;;
    esac
    s=${s#?}
done
echo
