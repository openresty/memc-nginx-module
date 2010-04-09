# vi:filetype=perl

use lib 'lib';
use Test::Nginx::Socket; # skip_all => 'ngx_memc storage commands do not work with the ngx_eval module';

plan tests => repeat_each() * 2 * blocks();

no_long_string();
#no_diff;

run_tests();

__DATA__

=== TEST 1: set in eval (NO subrequest in memory)
--- http_config
   upstream mc {
        server localhost:11984;
   }

--- config
    location = /main {
        echo_location /eval;
        echo_location /eval;
    }
   location = /eval {
       eval_subrequest_in_memory off;
       eval_override_content_type text/plain;
       eval $res {
           default_type 'text/plain';
           set $memc_cmd 'set';
           set $memc_key 'foo';
           set $memc_value 'myvalue';
           set $memc_exptime 24;
           memc_pass mc;
       }
       echo [$res];
   }

--- request
    GET /eval
--- response_body
[STORED]
--- timeout: 30
--- error_code: 200



=== TEST 2: set in eval (subrequest in memory)
--- http_config
   upstream mc {
        server localhost:11984;
   }

--- config
    location = /main {
        echo_location /eval;
        echo_location /eval;
    }
   location = /eval {
       eval_subrequest_in_memory on;
       eval_override_content_type text/plain;
       eval $res {
           default_type 'text/plain';
           set $memc_cmd 'set';
           set $memc_key 'foo';
           set $memc_value 'myvalue';
           set $memc_exptime 24;
           memc_pass mc;
       }
       echo [$res];
   }

--- request
    GET /eval
--- response_body
[STORED]
--- timeout: 30
--- error_code: 200

