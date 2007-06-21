package Cache::FastMmap::WithWin32;

=head1 NAME

Cache::FastMmap::WithWin32 - Uses an mmap'ed file to act as a shared memory interprocess cache

=head1 SYNOPSIS

  use Cache::FastMmap::WithWin32; 

  # Uses vaguely sane defaults
  $Cache = Cache::FastMmap->new(); # Yes, this is correct for this module

  # $Value must be a reference...
  $Cache->set($Key, $Value);
  $Value = $Cache->get($Key);

  $Cache = Cache::FastMmap->new(raw_values => 1);

  # $Value can't be a reference...
  $Cache->set($Key, $Value);
  $Value = $Cache->get($Key);

=head1 ABSTRACT

A shared memory cache through an mmap'ed file. It's core is written
in C for performance. It uses fcntl locking to ensure multiple
processes can safely access the cache at the same time. It uses
a basic LRU algorithm to keep the most used entries in the cache.

=head1 DESCRIPTION

This module is a fork of Cache::FastMmap by Rob Mueller to include the Win32
port by Ash Berlin, cos i got fed up waiting for Rob to release it. 
This distribution contains a file called Cache/FastMmap/WithWin32.pm that 
contains a C<Cache::FastMmap> package, so including this module allows your
code to run on both *nix and Win32 without modification (or at least that is
the plan)

Since I haven't changed anything in the interface or behaviour of the original
module, see L<Cache::FastMmap> for documentation.

=cut

# Modules/Export/XSLoader {{{
use 5.006;
use strict;
use warnings;
use bytes;

our $VERSION = '1.16.4';

use Cache::FastMmap::WithWin32::CImpl;

use constant FC_ISDIRTY => 1;
# }}}

sub new {
  my $Proto = shift;
  my $Class = ref($Proto) || $Proto;
  my %Args = @_;

  my $Self = {};
  bless ($Self, $Class);

  # Initialise C cache code
  my $Cache = Cache::FastMmap::WithWin32::CImpl::fc_new();

  # We bless the returned scalar ref into the same namespace,
  #  and store it in our own hash ref. We have to be sure
  #  that we only call C functions on this scalar ref, and
  #  only call PERL functions the hash ref we return
  bless ($Cache, 'Cache::FastMmap::WithWin32::CImpl');


  # Work out cache file and whether to init
  my $share_file = $Args{share_file};
  if (!$share_file) {
    $share_file = $Cache->fc_get_param('share_file');
  }
  $Self->{share_file} = $share_file;

  my $init_file = $Args{init_file} || 0;
  my $test_file = $Args{test_file} || 0;

  # Worth out unlink default if not specified
  if (!exists $Args{unlink_on_exit}) {
    $Args{unlink_on_exit} = -f($share_file) ? 0 : 1;
  }

  # Storing raw/storable values?
  my $raw_values = $Self->{raw_values} = int($Args{raw_values} || 0);

  # Need storable module if not using raw values
  if (!$raw_values) {
    eval "use Storable qw(freeze thaw); 1;"
      || die "Could not load Storable module: $@";
  }

  # Work out expiry time in seconds
  my $expire_time = $Args{expire_time} || 0;
  my %Times = (m => 60, h => 60*60, d => 24*60*60);
  $expire_time *= $Times{$1} if $expire_time =~ s/([mhd])$//i;
  $Self->{expire_time} = $expire_time = int($expire_time);

  # Function rounds to the nearest power of 2
  sub RoundPow2 { return int(2 ** int(log($_[0])/log(2)) + 0.1); }

  # Work out cache size
  my ($cache_size, $num_pages, $page_size);

  my %Sizes = (k => 1024, m => 1024*1024);
  if ($cache_size = $Args{cache_size}) {
    $cache_size *= $Sizes{$1} if $cache_size =~ s/([km])$//i;

    if ($num_pages = $Args{num_pages}) {
      $page_size = RoundPow2($cache_size / $num_pages);
      $page_size = 4096 if $page_size < 4096;

    } else {
      $page_size = $Args{page_size} || 65536;
      $page_size *= $Sizes{$1} if $page_size =~ s/([km])$//i;
      $page_size = 4096 if $page_size < 4096;

      # Increase num_pages till we exceed 
      $num_pages = 89;
      if ($num_pages * $page_size <= $cache_size) {
        while ($num_pages * $page_size <= $cache_size) {
          $num_pages = $num_pages * 2 + 1;
        }
      } else {
        while ($num_pages * $page_size > $cache_size) {
          $num_pages = int(($num_pages-1) / 2);
        }
        $num_pages = $num_pages * 2 + 1;
      }

    }

  } else {
    ($num_pages, $page_size) = @Args{qw(num_pages page_size)};
    $num_pages ||= 89;
    $page_size ||= 65536;
    $page_size *= $Sizes{$1} if $page_size =~ s/([km])$//i;
    $page_size = RoundPow2($page_size);
  }

  $cache_size = $num_pages * $page_size;
  @$Self{qw(cache_size num_pages page_size)}
    = ($cache_size, $num_pages, $page_size);

  # Number of slots to start in each page
  my $start_slots = int($Args{start_slots} || 0) || 89;

  # Save read through/write back/write through details
  my $write_back = ($Args{write_action} || 'write_through') eq 'write_back';
  @$Self{qw(context read_cb write_cb delete_cb)}
    = @Args{qw(context read_cb write_cb delete_cb)};
  @$Self{qw(cache_not_found allow_recursive write_back)}
    = (@Args{qw(cache_not_found allow_recursive)}, $write_back);
  @$Self{qw(empty_on_exit unlink_on_exit)}
    = @Args{qw(empty_on_exit unlink_on_exit)};

  # Save pid
  $Self->{pid} = $$;

  $Self->{Cache} = $Cache;

  # Setup cache parameters
  $Cache->fc_set_param('init_file', $init_file);
  $Cache->fc_set_param('test_file', $test_file);
  $Cache->fc_set_param('page_size', $page_size);
  $Cache->fc_set_param('num_pages', $num_pages);
  $Cache->fc_set_param('expire_time', $expire_time);
  $Cache->fc_set_param('share_file', $share_file);
  $Cache->fc_set_param('start_slots', $start_slots);

  # And initialise it
  $Cache->fc_init();

  # All done, return PERL hash ref as class
  return $Self;
}

sub get {
  my ($Self, $Cache) = ($_[0], $_[0]->{Cache});

  # Hash value, lock page, read result
  my ($HashPage, $HashSlot) = $Cache->fc_hash($_[1]);
  $Cache->fc_lock($HashPage);
  my ($Val, $Flags, $Found) = $Cache->fc_read($HashSlot, $_[1]);

  # Value not found, check underlying data store
  if (!$Found && (my $read_cb = $Self->{read_cb})) {

    # Callback to read from underlying data store
    # (unlock page first if we allow recursive calls
    $Cache->fc_unlock() if $Self->{allow_recursive};
    $Val = eval { $read_cb->($Self->{context}, $_[1]); };
    my $Err = $@;
    $Cache->fc_lock($HashPage) if $Self->{allow_recursive};

    # Pass on any error
    if ($Err) {
      $Cache->fc_unlock();
      die $Err;
    }

    # If we found it, or want to cache not-found, store back into our cache
    if (defined $Val || $Self->{cache_not_found}) {

      # Are we doing writeback's? If so, need to mark as dirty in cache
      my $write_back = $Self->{write_back};

      # If not using raw values, use freeze() to turn data 
      $Val = freeze(\$Val) if !$Self->{raw_values};

      # Get key/value len (we've got 'use bytes'), and do expunge check to
      #  create space if needed
      my $KVLen = length($_[1]) + (defined($Val) ? length($Val) : 0);
      $Self->_expunge_page(2, 1, $KVLen);

      $Cache->fc_write($HashSlot, $_[1], $Val, 0);
    }
  }

  # Unlock page and return any found value
  # Unlock is done only if we're not in the middle of a get_set() operation.
  $Cache->fc_unlock() unless $_[2] && $_[2]->{skip_unlock};

  # If not using raw values, use thaw() to turn data back into object
  if (!$Self->{raw_values}) {
    $Val = ${thaw($Val)} if defined $Val;
  }

  return $Val;
}

sub set {
  my ($Self, $Cache) = ($_[0], $_[0]->{Cache});

  # If not using raw values, use freeze() to turn data 
  my $Val = $Self->{raw_values} ? $_[2] : freeze(\$_[2]);

  # Hash value, lock page
  my ($HashPage, $HashSlot) = $Cache->fc_hash($_[1]);
  $Cache->fc_lock($HashPage) unless $_[3] && $_[3]->{skip_lock};

  # Are we doing writeback's? If so, need to mark as dirty in cache
  my $write_back = $Self->{write_back};

  # Get key/value len (we've got 'use bytes'), and do expunge check to
  #  create space if needed
  my $KVLen = length($_[1]) + (defined($Val) ? length($Val) : 0);
  $Self->_expunge_page(2, 1, $KVLen);

  # Now store into cache
  my $DidStore = $Cache->fc_write($HashSlot, $_[1], $Val, $write_back ? FC_ISDIRTY : 0);

  # Unlock page
  $Cache->fc_unlock();

  # If we're doing write-through, or write-back and didn't get into cache,
  #  write back to the underlying store
  if ((!$write_back || !$DidStore) && (my $write_cb = $Self->{write_cb})) {
    eval { $write_cb->($Self->{context}, $_[1], $_[2]); };
  }

  return $DidStore;
}

sub get_and_set {
  my ($Self, $Cache) = ($_[0], $_[0]->{Cache});

  my $Value = $Self->get($_[1], { skip_unlock => 1 });
  eval { $Value = $_[2]->($_[1], $Value); };
  my $Err = $@;
  $Self->set($_[1], $Value, { skip_lock => 1 });
  die $Err if $Err;

  return $Value;
}

sub remove {
  my ($Self, $Cache) = ($_[0], $_[0]->{Cache});

  # Hash value, lock page, read result
  my ($HashPage, $HashSlot) = $Cache->fc_hash($_[1]);
  $Cache->fc_lock($HashPage);
  my ($DidDel, $Flags) = $Cache->fc_delete($HashSlot, $_[1]);
  $Cache->fc_unlock();

  # If we deleted from the cache, and it's not dirty, also delete
  #  from underlying store
  if ((!$DidDel || ($DidDel && !($Flags & FC_ISDIRTY)))
     && (my $delete_cb = $Self->{delete_cb})) {
    eval { $delete_cb->($Self->{context}, $_[1]); };
  }
  
  return $DidDel;
}

sub clear {
  my $Self = shift;
  $Self->_expunge_all(1, 0);
}

sub purge {
  my $Self = shift;
  $Self->_expunge_all(0, 0);
}

sub empty {
  my $Self = shift;
  $Self->_expunge_all($_[0] ? 0 : 1, 1);
}

sub get_keys {
  my ($Self, $Cache) = ($_[0], $_[0]->{Cache});

  my $Mode = $_[1] || 0;
  return $Cache->fc_get_keys($Mode)
    if $Mode <= 1 || ($Mode == 2 && $Self->{raw_values});

  # If we're getting values as well, and they're not raw, unfreeze them
  my @Details = $Cache->fc_get_keys(2);
  for (@Details) { $_->{value} = ${thaw($_->{value})}; }
  return @Details;
}

sub multi_get {
  my ($Self, $Cache) = ($_[0], $_[0]->{Cache});

  # Hash value page key, lock page
  my ($HashPage, $HashSlot) = $Cache->fc_hash($_[1]);
  $Cache->fc_lock($HashPage);

  # For each key to find
  my ($Keys, %KVs) = ($_[2]);
  for (@$Keys) {

    # Hash key to get slot in this page and read
    my $FinalKey = "$_[1]-$_";
    (undef, $HashSlot) = $Cache->fc_hash($FinalKey);
    my ($Val, $Flags, $Found) = $Cache->fc_read($HashSlot, $FinalKey);
    next unless $Found;

    # If not using raw values, use thaw() to turn data back into object
    $Val = ${thaw($Val)} unless $Self->{raw_values};

    # Save to return
    $KVs{$_} = $Val;
  }

  # Unlock page and return any found value
  $Cache->fc_unlock();

  return \%KVs;
}

sub multi_set {
  my ($Self, $Cache) = ($_[0], $_[0]->{Cache});

  # Hash page key value, lock page
  my ($HashPage, $HashSlot) = $Cache->fc_hash($_[1]);
  $Cache->fc_lock($HashPage);

  # Loop over each key/value storing into this page
  my $KVs = $_[2];
  while (my ($Key, $Val) = each %$KVs) {

    # If not using raw values, use freeze() to turn data 
    $Val = freeze(\$Val) unless $Self->{raw_values};

    # Get key/value len (we've got 'use bytes'), and do expunge check to
    #  create space if needed
    my $FinalKey = "$_[1]-$Key";
    my $KVLen = length($FinalKey) + length($Val);
    $Self->_expunge_page(2, 1, $KVLen);

    # Now hash key and store into page
    (undef, $HashSlot) = $Cache->fc_hash($FinalKey);
    $Cache->fc_write($HashSlot, $FinalKey, $Val, 0);
  }

  # Unlock page
  $Cache->fc_unlock();

  return 1;
}

sub _expunge_all {
  my ($Self, $Cache, $Mode, $WB) = ($_[0], $_[0]->{Cache}, $_[1], $_[2]);

  # Repeat expunge for each page
  for (0 .. $Self->{num_pages}-1) {
    $Cache->fc_lock($_);
    $Self->_expunge_page($Mode, $WB, -1);
    $Cache->fc_unlock();
  }

}

sub _expunge_page {
  my ($Self, $Cache, $Mode, $WB, $Len) = ($_[0], $_[0]->{Cache}, @_[1 .. 3]);

  # If writeback mode, need to get expunged items to write back
  my $write_cb = $Self->{write_back} && $WB ? $Self->{write_cb} : undef;

  my @WBItems = $Cache->fc_expunge($Mode, $write_cb ? 1 : 0, $Len);

  for (@WBItems) {
    next if !($_->{flags} & FC_ISDIRTY);
    eval { $write_cb->($Self->{context}, $_->{key}, $_->{value}, $_->{expire_time}); };
  }
}

sub DESTROY {
  my ($Self, $Cache) = ($_[0], $_[0]->{Cache});

  # Expunge all entries on exit if requested and in parent process
  if ($Self->{empty_on_exit} && $Cache && $Self->{pid} == $$) {
    $Self->empty();
  }

  if ($Cache) {
    # The destructor calls close for us
    $Cache = undef;
    delete $Self->{Cache};
  }

  unlink($Self->{share_file})
    if $Self->{unlink_on_exit} && $Self->{pid} == $$;
}

sub CLONE {
  die "Cache::FastMmap::WithWin32 does not support threads sorry";
}


package #Hide From Pause
   Cache::FastMmap;

use base 'Cache::FastMmap::WithWin32';

1;

__END__

=head1 AUTHOR

Original *nix version by Rob Mueller E<lt>L<mailto:cpan@robm.fastmail.fm>E<gt>

Win32 port and refactoring by Ash Berlin L<< <ash@cpan.org> >>

VC6 fixes from Kenichi Ishigaki

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2003-2007 by FastMail IP Partners

Portions copyright (C) 2007 Ash Berlin

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself. 

=cut

