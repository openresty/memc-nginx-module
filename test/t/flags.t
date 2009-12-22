# vi:filetype=perl

use lib 'lib';
use Test::Nginx::LWP;

plan tests => repeat_each() * 2 * blocks();

#no_diff;

run_tests();

__DATA__

=== TEST 1: set flags and get flags
--- config
    location /flags {
        echo 'set foo BAR (flag: 1234567890)';
        echo_subrequest PUT '/memc?key=foo&flags=1234567890' -b BAR;

        echo 'get foo';
        echo_subrequest GET '/memc?key=foo';
    }
    location /memc {
        echo_before_body "status: $echo_response_status";
        echo_before_body "flags: $memc_flags";

        set $memc_key $arg_key;
        set $memc_flags $arg_flags;

        memc_pass 127.0.0.1:11984;
    }
--- request
    GET /flags
--- response_body eval
"set foo BAR (flag: 1234567890)
status: 201
flags: 1234567890
STORED\r
get foo
status: 200
flags: 1234567890
BAR"



=== TEST 2: test empty flags (default to 0)
--- config
    location /flags {
        echo 'set foo BAR (flag: EMPTY)';
        echo_subrequest PUT '/memc?key=foo' -b BAR;

        echo 'get foo';
        echo_subrequest GET '/memc?key=foo';
    }

    location /memc {
        echo_before_body "status: $echo_response_status";
        echo_before_body "flags: $memc_flags";

        set $memc_key $arg_key;
        set $memc_flags $arg_flags;

        memc_pass 127.0.0.1:11984;
    }
--- request
    GET /flags
--- response_body eval
"set foo BAR (flag: EMPTY)
status: 201
flags: 0
STORED\r
get foo
status: 200
flags: 0
BAR"



=== TEST 3: test empty flags (default to 0) (another form)
--- config
    location /flags {
        echo 'set foo BAR (flag: EMPTY)';
        echo_subrequest PUT '/memc?key=foo&flags=' -b BAR;

        echo 'get foo';
        echo_subrequest GET '/memc?key=foo';
    }

    location /memc {
        echo_before_body "status: $echo_response_status";
        echo_before_body "flags: $memc_flags";

        set $memc_key $arg_key;
        set $memc_flags $arg_flags;

        memc_pass 127.0.0.1:11984;
    }
--- request
    GET /flags
--- response_body eval
"set foo BAR (flag: EMPTY)
status: 201
flags: 0
STORED\r
get foo
status: 200
flags: 0
BAR"



=== TEST 4: add flags and get flags
--- config
    location /flags {
        echo 'flush_all';
        echo_subrequest GET '/memc?cmd=flush_all';

        echo 'add foo BAR (flag: 54321)';
        echo_subrequest POST '/memc?key=foo&flags=54321' -b BAR;

        echo 'get foo';
        echo_subrequest GET '/memc?key=foo';
    }
    location /memc {
        echo_before_body "status: $echo_response_status";
        echo_before_body "flags: $memc_flags";

        set $memc_cmd $arg_cmd;
        set $memc_key $arg_key;
        set $memc_flags $arg_flags;

        memc_pass 127.0.0.1:11984;
    }
--- request
    GET /flags
--- response_body eval
"flush_all
status: 200
flags: 
OK\r
add foo BAR (flag: 54321)
status: 201
flags: 54321
STORED\r
get foo
status: 200
flags: 54321
BAR"



=== TEST 5: set invalid flags
--- config
    location /allow {
        set $memc_cmd 'set';
        set $memc_key 'foo';
        set $memc_value 'nice';
        set $memc_flags 'invalid';
        memc_pass 127.0.0.1:11984;
    }
--- request
    GET /allow
--- response_body_like: 400 Bad Request
--- error_code: 400



=== TEST 6: set negative flags
--- config
    location /allow {
        set $memc_cmd 'set';
        set $memc_key 'sun';
        set $memc_value 'tree';
        set $memc_flags '-1';
        memc_pass 127.0.0.1:11984;
    }
--- request
    GET /allow
--- response_body_like: 400 Bad Request
--- error_code: 400

