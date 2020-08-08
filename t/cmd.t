# vi:filetype=

use lib 'lib';
use Test::Nginx::Socket;

plan tests => repeat_each() * (2 * blocks() + 3);

$ENV{TEST_NGINX_MEMCACHED_PORT} ||= 11211;

#no_diff;

run_tests();

__DATA__

=== TEST 1: bad cmd
--- config
    location /foo {
        set $memc_cmd blah;
        set $memc_key foo;
        memc_pass 127.0.0.1:$TEST_NGINX_MEMCACHED_PORT;
    }
--- request
    GET /foo
--- response_body_like: 400 Bad Request
--- error_code: 400
--- error_log
ngx_memc: unknown $memc_cmd "blah"



=== TEST 2: no default value for $memc_cmd for method COPY
--- config
    location /foo {
        set $memc_key foo;
        memc_pass 127.0.0.1:$TEST_NGINX_MEMCACHED_PORT;
    }
--- request
    COPY /foo
--- response_body_like: 400 Bad Request
--- error_code: 400
--- error_log
ngx_memc: $memc_cmd variable not found for HTTP COPY requests



=== TEST 3: bad cmd (case sensitive)
--- config
    location /foo {
        set $memc_cmd GET;
        set $memc_key foo;
        memc_pass 127.0.0.1:$TEST_NGINX_MEMCACHED_PORT;
    }
--- request
    GET /foo
--- response_body_like: 400 Bad Request
--- error_code: 400



=== TEST 4: explicit $memc_cmd in non-empty cmds_allowed list
--- config
    location /allow {
        set $memc_cmd version;
        memc_cmds_allowed get version;

        memc_pass 127.0.0.1:$TEST_NGINX_MEMCACHED_PORT;
    }
--- request
    GET /allow
--- response_body_like: ^VERSION \d+(\.\d+)+.*?\r\n$



=== TEST 5: explicit $memc_cmd in non-empty cmds_allowed list (in first)
--- config
    location /allow {
        set $memc_cmd version;
        memc_cmds_allowed version get;

        memc_pass 127.0.0.1:$TEST_NGINX_MEMCACHED_PORT;
    }
--- request
    GET /allow
--- response_body_like: ^VERSION \d+(\.\d+)+.*?\r\n$



=== TEST 6: explicit $memc_cmd NOT in non-empty cmds_allowed list
--- config
    location /allow {
        set $memc_cmd version;
        memc_cmds_allowed set get add delete;

        memc_pass 127.0.0.1:$TEST_NGINX_MEMCACHED_PORT;
    }
--- request
    GET /allow
--- response_body_like: 403 Forbidden
--- error_code: 403
--- error_log
ngx_memc: memcached command "version" not allowed



=== TEST 7: implicit $memc_cmd NOT in non-empty cmds_allowed list
--- config
    location /allow {
        memc_cmds_allowed set add delete version;

        set $memcached_key foo;
        memc_pass 127.0.0.1:$TEST_NGINX_MEMCACHED_PORT;
    }
--- request
    GET /allow
--- response_body_like: 403 Forbidden
--- error_code: 403



=== TEST 8: $memc_cmd has its default values when it's an empty string
--- config
    location /main {
        echo_read_request_body;
        echo 'set big2';
        echo_subrequest PUT '/memc?key=big2';

        echo 'get big2';
        echo_location '/memc?key=big2&cmd=get';
    }
    location /memc {
        set $memc_cmd $arg_cmd;
        set $memc_key $arg_key;
        memc_pass 127.0.0.1:$TEST_NGINX_MEMCACHED_PORT;
    }
--- request
POST /main
nice to meet you!
--- response_body eval
"set big2
STORED\r
get big2
nice to meet you!"



=== TEST 9: cas cmd $memc_unique_token variable dont't set
--- config
    location /foo {
        set $memc_cmd "cas";
        set $memc_key "test";
        set $memc_value "value";
        memc_pass 127.0.0.1:$TEST_NGINX_MEMCACHED_PORT;
    }
--- request
    GET /foo
--- response_body_like: 400 Bad Request
--- error_code: 400



=== TEST 10: cas cmd key not exists. memc response NOT_FOUND
--- config
    location /main {
        echo 'flush all';
        echo_location '/foo?cmd=flush_all';

        echo 'cas foo new value';
        echo_location '/foo?key=foo&cmd=cas&val=newvalue&token=123';
    }
    location /foo {
        set $memc_cmd $arg_cmd;
        set $memc_key $arg_key;
        set $memc_value $arg_val;
        set $memc_unique_token $arg_token;
        memc_pass 127.0.0.1:$TEST_NGINX_MEMCACHED_PORT;
    }
--- request
    GET /main
--- response_body_like
^flush all
OK\r
cas foo new value
<html>.*?404 Not Found.*$



=== TEST 10: cas cmd key exists. memc response EXISTS
--- config
    location /main {
        echo 'set foo val ok';
        echo_location '/foo?cmd=set&val=value&key=foo';

        echo 'cas foo new value';
        echo_location '/foo?key=foo&cmd=cas&val=newvalue&token=123';
    }
    location /foo {
        set $memc_cmd $arg_cmd;
        set $memc_key $arg_key;
        set $memc_value $arg_val;
        set $memc_unique_token $arg_token;
        memc_pass 127.0.0.1:$TEST_NGINX_MEMCACHED_PORT;
    }
--- request
    GET /main
--- response_body eval
"set foo val ok
STORED\r
cas foo new value
EXISTS\r\n"
