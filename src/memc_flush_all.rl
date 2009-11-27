%%{
    machine memc_flush_all;

    include memc_common "memc_common.rl";

    main := "OK\r\n"
          | error
          ;

}%%

