# vi:filetype=perl

use lib 'lib';
use Test::Nginx::LWP;

plan tests => 2 * blocks();

no_diff;

run_tests();

__DATA__

=== TEST 1: sanity
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

