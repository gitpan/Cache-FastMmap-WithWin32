use 5.006;
use ExtUtils::MakeMaker;

WriteMakefile(
    'NAME'          => 'Cache::FastMmap::WithWin32',
    'VERSION_FROM'  => 'lib/Cache/FastMmap.pm',
    'ABSTRACT_FROM' => 'lib/Cache/FastMmap.pm',
    'AUTHOR'        => 'Ash Berlin <cpan@cpan.org>',
    'PREREQ_PM'     => {
      'Storable' => 0
    },
    'DIR'           => [
      'Cache-FastMmap-CImpl'
    ],
#	    'OPTIMIZE' => '-g -DDEBUG',
);
