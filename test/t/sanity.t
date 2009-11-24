# vi:filetype=perl

use lib 'lib';
use Test::Nginx::LWP;

plan tests => 2 * blocks();

no_diff;

run_tests();

__DATA__

=== TEST 1: bad cmd
preset foo to bar...
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
preset foo to bar...
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
preset foo to bar...
--- config
    location /foo {
        set $memc_key foo;
        memc_pass 127.0.0.1:11984;
    }
--- request
    COPY /foo
--- response_body_like: 400 Bad Request
--- error_code: 400



=== TEST 4: sanity
preset foo to bar...
--- config
    location /foo {
        #set $memc_cmd get;
        set $memc_key foo;
        memc_pass 127.0.0.1:11984;
    }
--- request
    GET /foo
--- response_body chomp
bar

