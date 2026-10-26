#!/usr/bin/env bash
set -euo pipefail

image=${1:?Usage: security-smoke.sh IMAGE}
php=(docker run --rm --entrypoint /usr/local/bin/php "$image")

"${php[@]}" -r '
if (ini_get("session.upload_progress.enabled") || ini_get("pcre.jit")) {
    fwrite(STDERR, "unsafe session upload progress or PCRE JIT setting\n");
    exit(1);
}
if (extension_loaded("Zend OPcache") && ini_get("opcache.enable")) {
    fwrite(STDERR, "OPcache is enabled; the Fil-C port panics in zend_persist\n");
    exit(1);
}
echo PHP_VERSION, " session upload progress, PCRE JIT and OPcache off\n";
'

case "$("${php[@]}" -r 'echo PHP_MAJOR_VERSION, ".", PHP_MINOR_VERSION;')" in
  5.*|7.*)
    result=$("${php[@]}" -d memory_limit=2M -r '
if (memory_get_usage() <= 0) exit(3);
str_repeat("x", 8 * 1024 * 1024);
echo "memory_limit bypassed\n";
' 2>&1) && { echo "$result"; exit 1; }
    if ! grep -q 'Allowed memory size of 2097152 bytes exhausted' <<< "$result"; then
      echo "$result" >&2
      exit 1
    fi
    echo "memory_limit enforced"
    ;;
esac

"${php[@]}" -r '
$c = curl_init("https://www.php.net/");
curl_setopt($c, CURLOPT_NOBODY, true);
curl_setopt($c, CURLOPT_TIMEOUT, 30);
curl_setopt($c, CURLOPT_SSL_VERIFYPEER, true);
curl_setopt($c, CURLOPT_SSL_VERIFYHOST, 2);
if (!curl_exec($c) || curl_getinfo($c, CURLINFO_HTTP_CODE) != 200) {
    fwrite(STDERR, "HTTPS failed: " . curl_error($c) . "\n");
    exit(1);
}
echo "HTTPS verified\n";
'
