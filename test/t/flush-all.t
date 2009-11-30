# vi:filetype=perl

use lib 'lib';
use Test::Nginx::LWP;

plan tests => $Test::Nginx::LWP::RepeatEach * 2 * blocks();

no_diff;

run_tests();

__DATA__

=== TEST 1: flush_all
--- config
    location /flush {
        set $memc_cmd flush_all;
        memc_pass 127.0.0.1:11984;
    }
--- request
    GET /flush
--- response_body eval
"OK\r
"



=== TEST 2: set and flush and get
--- config
    location /main {
        echo 'set foo blah';
        echo_location '/memc?key=foo&cmd=set&val=blah';

        echo 'flush_all';
        echo_location '/memc?cmd=flush_all';

        echo 'get foo';
        echo_location '/memc?key=foo&cmd=get';
    }
    location /memc {
        echo_before_body "status: $echo_response_status";

        set $memc_cmd $arg_cmd;
        set $memc_key $arg_key;
        set $memc_value $arg_val;

        memc_pass 127.0.0.1:11984;
    }
--- request
    GET /main
--- response_body_like
^set foo blah
status: 201
STORED\r
flush_all
status: 200
OK\r
get foo
status: 404.*?404 Not Found.*$




