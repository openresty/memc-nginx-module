# vi:filetype=perl

use lib 'lib';
use Test::Nginx::Socket;

plan tests => repeat_each() * 2 * blocks();

#no_diff;

run_tests();

__DATA__

=== TEST 1: set only
--- http_config
   upstream mc {
        server agentzh.org:11984;
   }

--- config
   location = "/set" {
       set $memc_cmd 'set';
       set $memc_key 'jalla';
       set $memc_value 'myvalue';
       set $memc_exptime 24;
       memc_pass mc;
   }


   location = "/get" {
       set $memc_cmd 'get';
       set $memc_key 'jalla';
       memc_pass mc;
   }

   location = "/delete" {
       set $memc_cmd 'delete';
       set $memc_key 'jalla';
       memc_pass mc;
   }
   location = "/flush" {
       echo_location /get;
       #echo "";
       echo_location /delete;
   }
--- request
    GET /flush
--- response_body eval
"STORED\r\n"
--- error_code: 201
--- SKIP



=== TEST 2: set in a subrequest issued from an output filter
--- config
    location /memc {
        set $memc_cmd 'set';
        set $memc_key 'foo';
        set $memc_value 'blah';
        memc_pass 127.0.0.1:11984;
    }
    location /main {
        default_type 'text/html';
        add_before_body '/memc';
        echo '~~';
        add_after_body '/memc';
    }
--- request
GET /main
--- response_body eval
"STORED\r
~~
STORED\r
"

