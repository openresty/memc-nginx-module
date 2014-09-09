# vi:filetype=

use lib 'lib';
use Test::Nginx::Socket;

plan tests => repeat_each() * 2 * blocks();

$ENV{TEST_NGINX_MEMCACHED_PORT} ||= 11211;

#no_diff;

run_tests();

__DATA__

=== TEST 1: touch non-existent item
--- config
    location /main {
        echo 'flush_all';
        echo_location '/memc?cmd=flush_all';

        echo 'touch foo';
        echo_location '/memc?key=foo&cmd=touch&exptime=1';

        echo_blocking_sleep 1.6;
    }
    location /memc {
        echo_before_body "status: $echo_response_status";
        echo_before_body "exptime: $memc_exptime";

        set $memc_cmd $arg_cmd;
        set $memc_key $arg_key;
        set $memc_value $arg_val;
        set $memc_exptime $arg_exptime;

        memc_pass 127.0.0.1:$TEST_NGINX_MEMCACHED_PORT;
    }
--- request
    GET /main
--- response_body_like
^flush_all
status: 200
exptime: 
OK\r
touch foo
status: 404
exptime: 1
<html>.*?404 Not Found.*$



=== TEST 2: set and touch
--- config
    location /main {
        echo 'set foo bar';
        echo_location '/memc?cmd=set&key=foo&val=bar';

        echo 'touch foo 1';
        echo_location '/memc?key=foo&cmd=touch&exptime=1';
    }
    location /memc {
        echo_before_body "status: $echo_response_status";
        echo_before_body "exptime: $memc_exptime";

        set $memc_cmd $arg_cmd;
        set $memc_key $arg_key;
        set $memc_value $arg_val;
        set $memc_exptime $arg_exptime;

        memc_pass 127.0.0.1:$TEST_NGINX_MEMCACHED_PORT;
    }
--- request
    GET /main
--- response_body eval
"set foo bar
status: 201
exptime: 0
STORED\r
delete foo 1
status: 200
exptime: 1
TOUCHED\r
"
--- SKIP

