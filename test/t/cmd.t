# vi:filetype=perl

use lib 'lib';
use Test::Nginx::LWP;

plan tests => repeat_each() * 2 * blocks();

#no_diff;

run_tests();

__DATA__

=== TEST 1: bad cmd
--- config
    location /foo {
        set $memc_cmd blah;
        set $memc_key foo;
        memc_pass 127.0.0.1:11984;
    }
--- request
    GET /foo
--- response_body_like: 400 Bad Request
--- error_code: 400



=== TEST 2: no default value for $memc_cmd for method COPY
--- config
    location /foo {
        set $memc_key foo;
        memc_pass 127.0.0.1:11984;
    }
--- request
    COPY /foo
--- response_body_like: 400 Bad Request
--- error_code: 400



=== TEST 3: bad cmd (case sensitive)
--- config
    location /foo {
        set $memc_cmd GET;
        set $memc_key foo;
        memc_pass 127.0.0.1:11984;
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

        memc_pass 127.0.0.1:11984;
    }
--- request
    GET /allow
--- response_body_like: ^VERSION \d+(\.\d+)+\S*?\r\n$



=== TEST 5: explicit $memc_cmd in non-empty cmds_allowed list (in first)
--- config
    location /allow {
        set $memc_cmd version;
        memc_cmds_allowed version get;

        memc_pass 127.0.0.1:11984;
    }
--- request
    GET /allow
--- response_body_like: ^VERSION \d+(\.\d+)+\S*?\r\n$



=== TEST 6: explicit $memc_cmd NOT in non-empty cmds_allowed list
--- config
    location /allow {
        set $memc_cmd version;
        memc_cmds_allowed set get add delete;

        memc_pass 127.0.0.1:11984;
    }
--- request
    GET /allow
--- response_body_like: 403 Forbidden
--- error_code: 403



=== TEST 7: implicit $memc_cmd NOT in non-empty cmds_allowed list
--- config
    location /allow {
        memc_cmds_allowed set add delete version;

        set $memcached_key foo;
        memc_pass 127.0.0.1:11984;
    }
--- request
    GET /allow
--- response_body_like: 403 Forbidden
--- error_code: 403



=== TEST 8: $memc_cmd has its default values when it's an empty string
--- config
    location /main {
        echo 'set big';
        echo_subrequest POST '/memc?key=big';

        echo 'get big';
        echo_location '/memc?key=big&cmd=get';
    }
    location /memc {
        set $memc_cmd $arg_cmd;
        set $memc_key $arg_key;
        memc_pass 127.0.0.1:11984;
    }
--- request
POST /main
nice to meet you!
--- response_body eval
"set big
STORED\r
get big
nice to meet you!"

