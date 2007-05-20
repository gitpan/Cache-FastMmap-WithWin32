package Cache::FastMmap::WithWin32::CImpl;

=head1 NAME

Cache::FastMmap::WithWin32::CImpl - C code implementation for Cache::FastMmap::WithWin32

=head1 SYNOPSIS

Do not use this directly. Cache::FastMmap::WithWin32 uses this

=cut

# Modules/Export/XSLoader {{{
use 5.006;
use strict;
use warnings;

require XSLoader;
our $VERSION = '1.16.3';
XSLoader::load('Cache::FastMmap::WithWin32::CImpl', $VERSION);
# }}}

sub DESTROY {
  my $Self = shift;

  # Close any file before destruction
  $Self->fc_close();
}

1;

__END__

=head1 AUTHOR

Original Unix version by Rob Mueller E<lt>cpan@robm.fastmail.fmE<gt>

Win32 port by Ash Berlin <ash@cpan.org>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2003 by FastMail IP Partners

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself. 

=cut
