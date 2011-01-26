# vi:filetype=

use lib 'lib';
use Test::Nginx::Socket;

plan tests => repeat_each() * 2 * blocks();

$ENV{TEST_NGINX_MEMCACHED_PORT} ||= 11211;

#no_diff;

run_tests();

__DATA__

=== TEST 1: sanity
--- http_config
    upstream backend {
      server 127.0.0.1:$TEST_NGINX_MEMCACHED_PORT;
      server 127.0.0.1:$TEST_NGINX_MEMCACHED_PORT;
    }

--- config
    location /stats {
        set $memc_cmd stats;
        memc_pass backend;
    }
--- request
    GET /stats
--- response_body_like: ^(?:STAT [^\r]*\r\n)*END\r\n$



=== TEST 2: sanity
--- http_config
    upstream backend {
      server 127.0.0.1:$TEST_NGINX_MEMCACHED_PORT;
      server 127.0.0.1:11985;
      server 127.0.0.1:11986;
      #keepalive 2 single;
      #hash $arg_key;
    }

--- config
    location /memc {
        set $memc_cmd set;
        set $memc_key $arg_key;
        set $memc_value 'value';
        memc_pass backend;
    }
--- request
    GET /memc?key=dog
--- response_body
--- error_code: 201
--- SKIP



=== TEST 3: sanity with dynamic backend
--- http_config
    upstream backend {
      server 127.0.0.1:$TEST_NGINX_MEMCACHED_PORT;
    }

--- config
    location /stats {
        set $memc_cmd stats;
        memc_pass $arg_target;
    }
--- request
    GET /stats?target=backend
--- response_body_like: ^(?:STAT [^\r]*\r\n)*END\r\n$

