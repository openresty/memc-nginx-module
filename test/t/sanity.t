# vi:filetype=perl

use lib 'lib';
use Test::Nginx::LWP;

plan tests => 2 * blocks();

no_diff;

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



=== TEST 2: bad cmd (case sensitive)
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



=== TEST 3: no default value for $memc_cmd for method COPY
--- config
    location /foo {
        set $memc_key foo;
        memc_pass 127.0.0.1:11984;
    }
--- request
    COPY /foo
--- response_body_like: 400 Bad Request
--- error_code: 400



=== TEST 4: set only
--- config
    location /memc {
        set $memc_cmd $arg_cmd;
        set $memc_key $arg_key;
        set $memc_value $arg_val;
        memc_pass 127.0.0.1:11984;
    }
--- request
    GET /memc?key=foo&cmd=set&val=blah
--- response_body eval
"STORED\r\n"



=== TEST 5: set and get
--- config
    location /main {
        echo 'set foo blah';
        echo_location '/memc?key=foo&cmd=set&val=blah';

        echo 'get foo';
        echo_location '/memc?key=foo&cmd=get';
    }
    location /memc {
        set $memc_cmd $arg_cmd;
        set $memc_key $arg_key;
        set $memc_value $arg_val;
        memc_pass 127.0.0.1:11984;
    }
--- request
    GET /main
--- response_body eval
"set foo blah
STORED\r
get foo
blah"

