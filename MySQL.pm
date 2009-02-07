#####
#####  MySQL Library v3.14
#####
#####  Created by Dusty D. Wilson on 03 April 2003
#####  Modified by Kosta Jilkine on 13 January 2005
#####  Copyright 2005 Dusty D. Wilson.  All rights reserved.
#####
#####  Notice:  This library is incompatible with software developed
#####           for MySQL Library versions prior to v3.00.
#####
#####  The DBI and DBD::mysql Perl modules are required.
#####

#####  20040608T2340Z DW: Added "columns" subroutine.
#####  20040608T2350Z DW: Added "describe" subroutine.
#####  20040608T2350Z DW: Modified "columns" subroutine to receive information from "describe" subroutine.
#####  20040609T1735Z DW: Added "usage" comments for "columns" and "describe" subroutines.
#####  20040609T1939Z DW: Updated "hashinsert", "hashupdate", "hashinsertupdate" subroutines to use output from "describe" subroutine to filter input to use only available columns.
#####                     NOTE:  "hash*" subroutine matching functionality requires an exact match and will not use the updated filtering code.  This is to prevent erroneously deleting/updating mass selections of data in a table because no column or too few columns matched appropriately.
#####  20050113T0129Z KJ: Added "hashreplace".
#####  20050818T0550Z DW: v3.13 Changed to Hey::MySQL (was hey::MySQL) and packaged for first appearance on CPAN.


package Hey::MySQL;

our $VERSION = "3.14";

use DBI;

# usage:   $myHandle = Hey::MySQL->new;

sub new {
  my $class = shift;
  my $self = {
    _exists => 1,
    _server => undef,
    _port => undef,
    _database => undef,
    _username => undef,
    _password => undef
  };
  bless($self,$class);
  return($self);
}

# usage:   $myHandle->connect("database","username","password","server","port"); # <- The most verbose format.  Uses no defaults.
# usage:   $myHandle->connect("database","username","password","server:port"); # <- This format will auto-parse the hostname into server and port.
# usage:   $myHandle->connect("database","username","password","server"); # <- This format will use the default port of "3306"
# usage:   $myHandle->connect("database","username","password"); # <- This format will use the default host of "localhost:3306"
# usage:   $myHandle->connect("database"); # <- This format will only work if you have connected with this handle before.  It will use the previous values, replacing only the named database.
# usage:   $myHandle->connect; # <- This format will only work if you have connected with this handle before.  It will use the previous values.

sub connect {
  my $self = shift;
  return undef unless (defined($self->{_exists}));
  $self->{_database} = shift || $self->{_database};
  $self->{_username} = shift || $self->{_username};
  $self->{_password} = shift || $self->{_password};
  $self->{_server} = shift || $self->{_server} || "localhost";
  local $serverport = 0;
  if ($self->{_server} =~ s|:(\d+)$||) {
    $serverport = $1;
  }
  $self->{_port} = shift || $serverport || $self->{_port} || "3306";
  if ($self->{_sqlhandle} = DBI->connect("DBI:mysql:host=$self->{_server};database=$self->{_database}",$self->{_username},$self->{_password},{RaiseError => 0, PrintError => 0})) {
    return 1;
  }
  delete $self->{_sqlhandle};
  return undef;
}

# usage:   $myHandle->disconnect;

sub disconnect {
  my $self = shift;
  return undef unless (defined($self->{_sqlhandle}));
  if ($self->{_sqlhandle}->disconnect()) {
    delete $self->{_sqlhandle};
    return 1;
  } else {
    return undef;
  }
}

# usage:   $myHandle->error; # <- Will return last the error that occurred.

sub error {
  my $self = shift;
  return undef unless (defined($self->{_sqlhandle}));
  return $self->{_sqlhandle}->errstr;
}

# usage:   $myHandle->lastid; # <- Will return the last set auto_increment value.

sub lastid {
  my $self = shift;
  return undef unless (defined($self->{_sqlhandle}));
  return $self->row("SELECT LAST_INSERT_ID() AS id")->{id};
}

# usage:   $result = $myHandle->command("SOME SQL COMMAND"); # <- $result will usually return the number of rows acted upon.

sub command {
  my $self = shift;
  return undef unless (defined($self->{_sqlhandle}));
  my $command = shift;
  $command =~ s|\$|\\\$|g;
  local $do = $self->{_sqlhandle}->do($command);
  $do = 0 if ($do eq "0E0");
  return $do;
}

# usage:   @result = $myHandle->query("SOME SQL COMMAND"); # <- @result will return an array of hashrefs.

sub query {
  my $self = shift;
  return undef unless (defined($self->{_sqlhandle}));
  my $query = shift;
  $query =~ s|\$|\\\$|g;
  local @returnquery;
  local $returndata;
  local $dbquery = $self->{_sqlhandle}->prepare($query);
  if ($dbquery->execute) {
    while ($returndata = $dbquery->fetchrow_hashref()) {
      push(@returnquery,$returndata);
    }
    $dbquery->finish;
    return @returnquery;
  }
  return undef;
}

# usage:   $result = $myHandle->row("SOME SQL COMMAND"); # <- $result will return a hashref.

sub row {
  my $self = shift;
  return undef unless (defined($self->{_sqlhandle}));
  my $query = shift;
  $query =~ s|\$|\\\$|g;
  local $returndata;
  local $dbquery = $self->{_sqlhandle}->prepare($query);
  if ($dbquery->execute) {
    $returndata = $dbquery->fetchrow_hashref();
    $dbquery->finish;
    return $returndata;
  }
  return undef;
}

# usage:   $count = $myHandle->hashinsert("tablename",\@rows); # <- $count will return the number of rows inserted.  @rows is an array of hashrefs that will be used to create new rows in the named table.

sub hashinsert {
  my $self = shift;
  local $tablename = shift or return undef;
  local $toadd = shift or return undef;
  local @addarray;
  if (ref($toadd) eq "ARRAY") {
   @addarray = @{$toadd};
  } elsif (ref($toadd) eq "HASH") {
    push(@addarray,$toadd);
  } else {
    return undef;
  }
  local $keys = "";
  local $values = "";
  local $notFirstLoop = 0;
  local $describe = $self->describe($tablename);
  foreach (@addarray) {
    local $intval = "";
    foreach $key (sort(keys(%{$_}))) {
      if ($describe->{$key}) {
        $keys .= "`$key`," unless ($notFirstLoop);
        ($val = $_->{$key}) =~ s|(["'\\])|\\$1|g;
        $intval .= qq|"$val",|;
      }
    }
    $notFirstLoop = 1;
    $intval =~ s|,$||;
    $values .= "($intval),";
  }
  $keys =~ s|,$||;
  $values =~ s|,$||;
  return $self->command("INSERT INTO `$tablename` ($keys) VALUES $values");
}

# usage:   $count = $myHandle->hashreplace("tablename",\@rows); # <- $count will return the number of rows inserted.  @rows is an array of hashrefs that will be used to create new rows in the named table.

sub hashreplace {
  my $self = shift;
  local $tablename = shift or return undef;
  local $toadd = shift or return undef;
  local @addarray;
  if (ref($toadd) eq "ARRAY") {
   @addarray = @{$toadd};
  } elsif (ref($toadd) eq "HASH") {
    push(@addarray,$toadd);
  } else {
    return undef;
  }
  local $keys = "";
  local $values = "";
  local $notFirstLoop = 0;
  local $describe = $self->describe($tablename);
  foreach (@addarray) {
    local $intval = "";
    foreach $key (sort(keys(%{$_}))) {
      if ($describe->{$key}) {
        $keys .= "`$key`," unless ($notFirstLoop);
        ($val = $_->{$key}) =~ s|(["'\\])|\\$1|g;
        $intval .= qq|"$val",|;
      }
    }
    $notFirstLoop = 1;
    $intval =~ s|,$||;
    $values .= "($intval),";
  }
  $keys =~ s|,$||;
  $values =~ s|,$||;
  return $self->command("REPLACE INTO `$tablename` ($keys) VALUES $values");
}

# usage:   $count = $myHandle->hashinsertupdate("tablename",\%rowifnew,\%rowifupdate); # <- $count will return the number of rows inserted/updated.  \%rowifnew is the hashref that will be used to create the new row in the named table.  \%rowifupdate is the data that will replace what matches the keys in "\%rowifnew" if it already exists.

sub hashinsertupdate {
  my $self = shift;
  local $tablename = shift or return undef;
  local $newrow = shift or return undef;
  local $updaterow = shift || $newrow;
  unless (ref($newrow) eq "HASH") {
    return undef;
  }
  unless (ref($updaterow) eq "HASH") {
    return undef;
  }
  local $describe = $self->describe($tablename);
  local $newrowsql;
  foreach $key (sort(keys(%{$newrow}))) {
    if ($describe->{$key}) {
      ($val = $newrow->{$key}) =~ s|(["'\\])|\\$1|g;
      $newrowsql .= qq|`$key`="$val",|;
    }
  }
  $newrowsql =~ s|,$||;
  local $updaterowsql;
  foreach $key (sort(keys(%{$updaterow}))) {
    if ($describe->{$key}) {
      ($val = $updaterow->{$key}) =~ s|(["'\\])|\\$1|g;
      $updaterowsql .= qq|`$key`="$val",|;
    }
  }
  $updaterowsql =~ s|,$||;
  return $self->command("INSERT INTO `$tablename` $newrowsql ON DUPLICATE KEY UPDATE $updaterowsql");
}

# usage:   $count = $myHandle->hashupdate("tablename",\%match,\%set); # <- $count will return the number of rows updated.  %match is a hashref that will be used to match rows in the named table.  %set is a hashref that will be used to update matched rows in the named table.

sub hashupdate {
  my $self = shift;
  local $tablename = shift or return undef;
  local $tomatch = shift or return undef;
  local $toset = shift or return undef;
  unless (ref($tomatch) eq "HASH") {
    return undef;
  }
  unless (ref($toset) eq "HASH") {
    return undef;
  }
  local $describe = $self->describe($tablename);
  local $values;
  foreach $key (sort(keys(%{$toset}))) {
    if ($describe->{$key}) {
      ($val = $toset->{$key}) =~ s|(["'\\])|\\$1|g;
      $values .= qq|`$key`="$val",|;
    }
  }
  $values =~ s|,$||;
  local $match;
  foreach $key (sort(keys(%{$tomatch}))) {
    ($val = $tomatch->{$key}) =~ s|(["'\\])|\\$1|g;
    $match .= qq|`$key`="$val" AND |;
  }
  $match =~ s| AND $||;

  use IO::All;
  return $self->command("UPDATE `$tablename` SET $values WHERE $match");
}

# usage:   $count = $myHandle->hashdelete("tablename",\%match); # <- $count will return the number of rows deleted.  %match is a hashref that will be used to match rows in the named table.

sub hashdelete {
  my $self = shift;
  local $tablename = shift or return undef;
  local $tomatch = shift or return undef;
  unless (ref($tomatch) eq "HASH") {
    return undef;
  }
  local $match;
  foreach $key (sort(keys(%{$tomatch}))) {
    ($val = $tomatch->{$key}) =~ s|(["'\\])|\\$1|g;
    $match .= qq|`$key`="$val" AND |;
  }
  $match =~ s| AND $||;
  return $self->command("DELETE FROM `$tablename` WHERE $match");
}

# usage:   @columns = $myHandle->columns("tablename"); # <- returns an array of column names for the specified table

sub columns {
  my $self = shift;
  local $tablename = shift or return undef;
  local $columns = $self->describe($tablename);
  return keys(%{$columns});
}

# usage:   $describedTable = $myHandle->describe("tablename"); # <- returns a multi-dimensional hash reference (nested refs) describing each column of the specified table

sub describe {
  my $self = shift;
  local $tablename = shift or return undef;
  local @describe = $self->query("DESCRIBE `$tablename`");
  local $out;
  local $thisRow;
  foreach $thisRow (@describe) {
    local $item;
    local $thisColumnName;
    foreach $thisColumnName (keys(%{$thisRow})) {
      $item->{lc($thisColumnName)} = $thisRow->{$thisColumnName};
    }
    if ($item->{type} =~ s|^(enum)\((.*?)\)$|$1|i) {
      local $enum = $2;
      local $enumItem;
      foreach $enumItem (split(/,/, $enum)) {   ### <- There must be a better way to do this.  Goal:  Seperate items in list by commas, but ignore commas within "/' sections.  Remove "/' container.  Could a CPAN module help with this?  Text::Balanced or something similar?
        $enumItem =~ s|^'||;                    ### ^^^
        $enumItem =~ s|'$||;                    ### ^^^
        push(@{$item->{items}}, $enumItem);     ### ^^^
      }                                         ### ^^^
    }
    $out->{$thisRow->{Field}} = $item;
  }
  return $out;
}

1;


__END__
=head1 NAME

Hey::MySQL - Simple method for interacting with MySQL (don't use it, not maintained)

=head1 DESCRIPTION

This is a poorly written module to access MySQL.
Unless you already have code tied to it, don't start using it.
It's no longer maintained.
If you are using it for some reason, let me know.

Use L<DBI> instead.
Or one of the neato abstracting modules.

=head1 SEE ALSO

The source code for this module.
There are comments that give documentation.
Obviously I wasn't any good at writing documentation when this was created.

=head1 LICENSE

Use it any way you want, though using it at all is not recommended.
We're not liable for whatever non-good stuff that results.

=cut
