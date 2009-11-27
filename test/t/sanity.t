# vi:filetype=perl

use lib 'lib';
use Test::Nginx::LWP;

plan tests => $Test::Nginx::LWP::RepeatEach * 2 * blocks();

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
--- error_code: 201



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



=== TEST 6: flush_all
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



=== TEST 7: set and flush and get
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



=== TEST 8: set and get empty values
--- config
    location /main {
        echo 'flush all';
        echo_location '/memc?cmd=flush_all';

        echo 'set foo blah';
        echo_location '/memc?key=foo&cmd=set&val=';

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
"flush all
OK\r
set foo blah
STORED\r
get foo
"



=== TEST 9: add
--- config
    location /main {
        echo 'flush all';
        echo_location '/memc?cmd=flush_all';

        echo 'add foo blah';
        echo_location '/memc?key=foo&cmd=add&val=added';

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
--- response_body eval
"flush all
status: 200
OK\r
add foo blah
status: 201
STORED\r
get foo
status: 200
added"



=== TEST 10: set using POST
--- config
    location /main {
        echo 'flush all';
        echo_location '/memc?cmd=flush_all';

        echo 'set foo';
        echo_subrequest POST '/memc?key=foo&cmd=set';

        echo 'get foo';
        echo_location '/memc?key=foo&cmd=get';
    }
    location /memc {
        echo_before_body "status: $echo_response_status";

        set $memc_cmd $arg_cmd;
        set $memc_key $arg_key;
        #set $memc_value $arg_val;

        memc_pass 127.0.0.1:11984;
    }
--- request
POST /main
hello, world
--- response_body eval
"flush all
status: 200
OK\r
set foo
status: 201
STORED\r
get foo
status: 200
hello, world"



=== TEST 11: default REST interface when no $memc_cmd is set
--- config
    location /main {
        echo 'set foo FOO';
        echo_subrequest PUT '/memc?key=foo' -b FOO;

        echo 'get foo';
        echo_subrequest GET '/memc?key=foo';
        echo;

        echo 'set foo BAR';
        echo_subrequest PUT '/memc?key=foo' -b BAR;

        echo 'get foo';
        echo_subrequest GET '/memc?key=foo';
        echo;
    }
    location /memc {
        echo_before_body "status: $echo_response_status";

        set $memc_key $arg_key;
        #set $memc_value $arg_val;

        memc_pass 127.0.0.1:11984;
    }
--- request
GET /main
--- response_body eval
"set foo FOO
status: 201
STORED\r
get foo
status: 200
FOO
set foo BAR
status: 201
STORED\r
get foo
status: 200
BAR
"



=== TEST 12: default REST interface when no $memc_cmd is set (read client req body)
--- config
    location /main {
        echo 'set foo <client req body>';
        echo_subrequest PUT '/memc?key=foo';

        echo 'get foo';
        echo_subrequest GET '/memc?key=foo';
        echo;

        echo 'set foo BAR';
        echo_subrequest PUT '/memc?key=foo' -b BAR;

        echo 'get foo';
        echo_subrequest GET '/memc?key=foo';
        echo;
    }
    location /memc {
        echo_before_body "status: $echo_response_status";

        set $memc_key $arg_key;
        #set $memc_value $arg_val;

        memc_pass 127.0.0.1:11984;
    }
--- request
POST /main
rock
--- response_body eval
"set foo <client req body>
status: 201
STORED\r
get foo
status: 200
rock
set foo BAR
status: 201
STORED\r
get foo
status: 200
BAR
"



=== TEST 13: default REST interface when no $memc_cmd is set (read client req body)
--- config
    location /main {
        echo 'set foo <client req body>';
        echo_subrequest PUT '/memc?key=foo';

        echo 'get foo';
        echo_subrequest GET '/memc?key=foo';
        echo;

        echo 'add foo BAR';
        echo_subrequest POST '/memc?key=foo' -b BAR;

        echo 'get foo';
        echo_subrequest GET '/memc?key=foo';
        echo;
    }
    location /memc {
        echo_before_body "status: $echo_response_status";

        set $memc_key $arg_key;
        #set $memc_value $arg_val;

        memc_pass 127.0.0.1:11984;
    }
--- request
POST /main
howdy
--- response_body eval
"set foo <client req body>
status: 201
STORED\r
get foo
status: 200
howdy
add foo BAR
status: 200
NOT_STORED\r
get foo
status: 200
howdy
"



=== TEST 14: test replace (stored) (without sleep)
--- config
    location /main {
        echo 'flush all';
        echo_location '/memc?cmd=flush_all';
        #echo_sleep 0.001;

        echo 'add foo blah';
        echo_location '/memc?key=foo&cmd=add&val=added';

        echo 'replace foo bah';
        echo_location '/memc?key=foo&cmd=replace&val=bah';

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
--- response_body eval
"flush all
status: 200
OK\r
add foo blah
status: 201
STORED\r
replace foo bah
status: 201
STORED\r
get foo
status: 200
bah"



=== TEST 15: test replace (stored) (with sleep)
--- config
    location /main {
        echo 'flush all';
        echo_location '/memc?cmd=flush_all';
        echo_sleep 0.001;

        echo 'add foo blah';
        echo_location '/memc?key=foo&cmd=add&val=added';
        #echo_sleep 0.001;

        echo 'replace foo bah';
        echo_location '/memc?key=foo&cmd=replace&val=bah';
        #echo_sleep 0.001;

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
--- response_body eval
"flush all
status: 200
OK\r
add foo blah
status: 201
STORED\r
replace foo bah
status: 201
STORED\r
get foo
status: 200
bah"
--- skip_nginx: 2: < 0.8.11



=== TEST 16: test replace (not stored)
--- config
    location /main {
        echo 'flush all';
        echo_location '/memc?cmd=flush_all';

        echo 'replace foo bah';
        echo_location '/memc?key=foo&cmd=replace&val=bah';

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
flush all
status: 200
OK\r
replace foo bah
status: 200
NOT_STORED\r
get foo
status: 404.*?404 Not Found.*$



=== TEST 17: test append (stored)
--- config
    location /main {
        echo 'flush all';
        echo_location '/memc?cmd=flush_all';

        echo 'add foo hello';
        echo_location '/memc?key=foo&cmd=add&val=hello';

        echo 'append foo ,world';
        echo_location '/memc?key=foo&cmd=append&val=,world';

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
--- response_body eval
"flush all
status: 200
OK\r
add foo hello
status: 201
STORED\r
append foo ,world
status: 201
STORED\r
get foo
status: 200
hello,world"



=== TEST 18: test append (not stored)
--- config
    location /main {
        echo 'flush all';
        echo_location '/memc?cmd=flush_all';

        echo 'append foo ,world';
        echo_location '/memc?key=foo&cmd=append&val=,world';

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
flush all
status: 200
OK\r
append foo ,world
status: 200
NOT_STORED\r
get foo
status: 404.*?404 Not Found.*$



=== TEST 19: test prepend (stored)
--- config
    location /main {
        echo 'flush all';
        echo_location '/memc?cmd=flush_all';

        echo 'add foo hello';
        echo_location '/memc?key=foo&cmd=add&val=hello';

        echo 'prepend foo world,';
        echo_location '/memc?key=foo&cmd=prepend&val=world,';

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
--- response_body eval
"flush all
status: 200
OK\r
add foo hello
status: 201
STORED\r
prepend foo world,
status: 201
STORED\r
get foo
status: 200
world,hello"



=== TEST 20: test prepend (not stored)
--- config
    location /main {
        echo 'flush all';
        echo_location '/memc?cmd=flush_all';

        echo 'prepend foo world,';
        echo_location '/memc?key=foo&cmd=prepend&val=world,';

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
flush all
status: 200
OK\r
prepend foo world,
status: 200
NOT_STORED\r
get foo
status: 404.*?404 Not Found.*$



=== TEST 21: the "version" command
--- config
    location /ver {
        set $memc_cmd version;
        memc_pass 127.0.0.1:11984;
    }
--- request
    GET /ver
--- response_body_like: ^VERSION \d+(\.\d+)+\S*?\r\n$

