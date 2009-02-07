use 5.005;
use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    'NAME'		=> 'Hey::MySQL',
    'VERSION_FROM'	=> 'MySQL.pm', # finds $VERSION
    'PREREQ_PM'		=> {
        'DBI'           => '1.43',
        'DBD::mysql'    => '2.9004',
        'IO::All'       => '0.1',
    },
    ($] >= 5.005 ?    ## Add these new keywords supported since 5.005
      (AUTHOR     => 'Dusty Wilson <cpan-Hey-MySQL@dusty.hey.nu>') : ()),
);
