# vi:filetype=perl

use lib 'lib';
use Test::Nginx::LWP;

plan tests => $Test::Nginx::LWP::RepeatEach * 2 * blocks();

#no_diff;

run_tests();

__DATA__

=== TEST 1: sanity
--- config
    location /stats {
        set $memc_cmd stats;
        memc_pass 127.0.0.1:11984;
    }
--- request
    GET /stats
--- response_body_like: ^(?:STAT [^\r]*\r\n)*END\r\n$

