use 5.006;
use ExtUtils::MakeMaker;

WriteMakefile(
    'NAME'          => 'Cache::FastMmap::WithWin32::CImpl',
    'AUTHOR'        => 'Ash Berlin <ash@cpan.org>',
    'VERSION_FROM'  => 'CImpl.pm',
    'LIBS'          => [''],
    'INC'           => '-I.',
    'OBJECT'        => 'CImpl.o mmap_cache.o ' . ($^O eq 'MSWin32' ? 'win32.o' : 'unix.o'),
	    'DEFINE'        => '-g -DDEBUG',
);
