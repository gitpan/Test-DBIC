package Test::DBIC;

=head1 NAME

Test::DBIC - Facilitates Automated Testing for DBIx::Class

=head1 SYNOPSIS

In your test script add this block:

  BEGIN {
      use Test::DBIC;

      eval 'require DBD::SQLite';
      if ($@) {
          plan skip_all => 'DBD::SQLite not installed';
      } else {
          plan tests => 1;  # change this to the correct number of tests
      }
  };

  my $schema = Test::DBIC->init_schema(
      sample_data_file => 't/var/sample_data.txt',
  );

=head1 DESCRIPTION

This module facilitates testing of DBIx::Class components.

=cut

use strict;
use warnings;

our $VERSION = '0.01001';

BEGIN {
    # little trick by Ovid to pretend to subclass+exporter Test::More
    use base qw/Test::Builder::Module Class::Accessor::Grouped/;
    use Test::More;
    use File::Spec::Functions qw/catfile catdir/;

    @Test::DBIC::EXPORT = @Test::More::EXPORT;

    __PACKAGE__->mk_group_accessors('inherited', qw/db_dir db_file/);
};

=head2 Methods

=over 4

=item db_dir

Gets/sets the directory where SQLite database files will be stored.

  Test::DBIC->db_dir(catdir('t', 'var'));

=cut

__PACKAGE__->db_dir(catdir('t', 'var'));

=item db_file

Gets/sets the name of the main SQLite database file.

  Test::DBIC->db_file('test.db');

=cut

__PACKAGE__->db_file('test.db');

=item init_schema

Removes the test database under C<db_dir> and then
sets up a new test database and returns a DBIx::Class
schema object for your test to use.  

Parameters are:

=over 4

=item existing_namespace

Look for ResultSource (table definition) classes under this
namespace, rather than in the schema namespace specified by
C<schema_class>.

=item namespace

Subclass ResultSet objects into this namespace.  Objects that you
get back will be under this namespace.

=item no_deploy

If true, will not set up a test database nor populate it with
sample data.

=item sqlt_deploy

If true, will call the experimental $schema->deploy().  Also triggered
if the DBICTEST_SQLT_DEPLOY environment variable is set.

The default is to read the file t/lib/sqlite.sql and execute the SQL
within.

=item eval_deploy

If true, and if using C<sqlt_deploy>, will not die when the test
database fails to initialize.

=item no_populate

If true, will not populate the test database with sample data.

=item clear

If true, will delete any existing data in the test database
before populating with sample data.

=item sample_data

Specifies data to use when populating the test database.

The format is:

  'sample_data' => [
      ResultSourceName => [
          ['column1', 'column2', 'column3'],
          ['data1', 'data2', 'data3'],
          ['data1', 'data2', 'data3'],
      ],
      ResultSourceName => [
          ...
      ],
  ],

The ResultSourceName is the string passed to $schema->resultset.

=item sample_data_file

Specifies a file which contains data to use when populating
the test database.

The format for the file is:

  ResultSourceName
  column1, column2, column3
  data1, data2, data3
  data1, data2, data3
  ---
  ResultSourceName
  ...

The ResultSourceName is the string passed to $schema->resultset.

Data for multiple tables may be specified, with a separator line
of C<---> between them.

=item schema_class

The name of the DBIx::Class schema to use.  Defaults to
C<Test::DBIC::Schema>.

=back

=cut

## cribbed and modified from DBICTest in DBIx::Class tests
sub init_schema {
    my ($self, %args) = @_;
    my $db_dir  = $args{'db_dir'}  || $self->db_dir;
    my $db_file = $args{'db_file'} || $self->db_file;
    my $namespace = $args{'namespace'} || 'DBIC::TestSchema';
    my $schema_class = $args{'schema_class'} || 'Test::DBIC::Schema';
    my $db = catfile($db_dir, $db_file);

    eval 'use DBD::SQLite';
    if ($@) {
       BAIL_OUT('DBD::SQLite not installed');

        return;
    };

    eval "use $schema_class";
    if ($@) {
        BAIL_OUT("Could not load $schema_class: $@");

        return;
    };

    if (opendir DIR, $db_dir) {
        my @files = grep { /^$db_file[-\.]/ } readdir DIR;
        closedir DIR;
        foreach my $file (@files) {
            if ($file =~ /^([-\@\w.]+)$/) {
                $file = $db_dir . '/' . $1; # remove taintedness
            }
            unlink($file) if -e $file;
        }
    }
    unlink($db) if -e $db;
    mkdir($db_dir) unless -d $db_dir;

    my $dsn = 'dbi:SQLite:' . $db;
    my $schema = $schema_class->compose_namespace($namespace)->connect($dsn);
    $schema->storage->on_connect_do([
        'PRAGMA synchronous = OFF',
        'PRAGMA temp_store = MEMORY'
    ]);

    unless ($args{'no_deploy'}) {
        __PACKAGE__->deploy_schema($schema, %args);
        __PACKAGE__->populate_schema($schema, %args) unless $args{'no_populate'};
    }

    return $schema;
};

=item deploy_schema

Called by C<init_schema>.  Creates tables in the test database.

=cut

sub deploy_schema {
    my ($self, $schema, %options) = @_;
    my $eval = $options{'eval_deploy'};

    eval 'use SQL::Translator';
    if (!$@ && ($options{'sqlt_deploy'} or $ENV{"DBICTEST_SQLT_DEPLOY"})) {
        eval {
            $schema->deploy();
        };
        if ($@ && !$eval) {
            die $@;
        };
    } else {
        my $sql = slurp(catfile('t', 'lib', 'sqlite.sql'));
        if ($sql) {
            my (@tables) = $sql =~ m/create\s+table\s+(.+?)(?:\s*\()/gi;
            my %seen = ();
            foreach my $table (@tables) {
                if (index($table, '.') > 0) {
                    my ($prefix) = $table =~ m/^(.+?)\./;
                    # diag "$table is under schema $prefix\n";
                    next if $seen{$prefix}++;
                    my $dbh = $schema->storage->dbh;
                    if ($dbh->{Driver}{Name} eq 'SQLite') {
                        my $db_dir  = $options{'db_dir'}  || $self->db_dir;
                        my $db_file = $options{'db_file'} || $self->db_file;
                        my $db = catfile($db_dir, $db_file);
                        # diag "attaching file $db.$prefix as schema $prefix\n";
                        $dbh->do("attach '$db.$prefix' as $prefix");
                    }
                }
            }
            eval {
                ($schema->storage->dbh->do($_) || print "Error on SQL: $_\n") for split(/;\n/, $sql);
            };
            if ($@ && !$eval) {
                die $@;
            };
        } else {
            diag "cannot initialize database\n";
        }
    };
};

sub slurp {
    my $file = shift;
    my $content;
    if (open IN, $file) {;
        { local $/ = undef; $content = <IN>; }
        close IN;
    } else {
        diag "failed to read $file\n";
    }
    return $content;
}

=item clear_schema

Called before populating the test database, if C<clear> has been
set to true.  Deletes data from known tables.

=cut

sub clear_schema {
    my ($self, $schema, %options) = @_;

    foreach my $source ($schema->sources) {
        $schema->resultset($source)->delete_all;
    };
};

=item populate_schema

Called by C<init_schema>.  Loads sample data into the test database.

=cut

sub populate_schema {
    my ($self, $schema, %options) = @_;
    
    if ($options{'clear'}) {
        $self->clear_schema($schema, %options);
    };

    if ($options{'sample_data_file'}) {
        $self->populate_from_file($schema, %options);
    }
    if ($options{'sample_data'}) {
        $self->populate_from_array($schema, %options);
    }
};

sub populate_from_file {
    my ($self, $schema, %options) = @_;
    # expects a file in the format
    # tableclass_name
    # column1, column2, column3
    # data1, data2, data3
    # data1, data2, data3
    # ---
    # tableclass_name
    # ...
    use IO::File;
    my $fh = IO::File->new($options{'sample_data_file'}) || diag "failed to read sample data file: $options{'sample_data_file'}: $!\n";
    return unless $fh;
    my ($tableclass, @columns, @data);
    while (my $line = $fh->getline) {
        chomp($line);
        if ($line eq '---') {
            if ($tableclass and @columns and @data) {
                #diag "populating $tableclass with " . scalar(@data) . " rows\n";
                $self->populate_table($schema, \%options, $tableclass, \@columns, \@data);
            }
            undef $tableclass;
            @columns = ();
            @data = ();
        } elsif (!defined($tableclass)) {
            $tableclass = $line;
            #diag "preparing to populate $tableclass\n";
        } elsif (!@columns) {
            @columns = split(/,\s*/, $line);
            #diag "$tableclass has columns: " . join(', ', @columns) . "\n";
        } else {
            my @row = split(/,\s*/, $line);
            push @data, \@row;
        }
    }
    if ($tableclass and @columns and @data) {
        #diag "populating $tableclass with " . scalar(@data) . " rows\n";
        $self->populate_table($schema, \%options, $tableclass, \@columns, \@data);
    }
    undef $tableclass;
    @columns = ();
    @data = ();
}

sub populate_from_array {
    my ($self, $schema, %options) = @_;
    return unless (ref($options{'sample_data'}) eq 'ARRAY');
    my $c = 0;
    while ($c < @{$options{'sample_data'}}) {
        my $tableclass = $options{'sample_data'}[$c++];
        my $data = $options{'sample_data'}[$c++];
        my $columns = shift(@$data);
        $self->populate_table($schema, \%options, $tableclass, $columns, $data);
        unshift(@$data, $columns); # put things back how we found them
    }
}

sub populate_table {
    my ($self, $schema, $options, $tableclass, $columns, $data) = @_;
    if (my $existing_namespace = $options->{'existing_namespace'} || '') {
        $schema->load_classes({
            $existing_namespace => [$tableclass],
        });
    }
    $schema->populate($tableclass, [
        $columns,
        @$data,
    ]);
}

=back

=cut

1;
__END__

=head1 SEE ALSO

L<DBIx::Class>

=head1 AUTHOR

Nathan Gray E<lt>kolibrie@cpan.orgE<gt>

based on DBICTest (from the testsuite of DBIx::Class)
and DBIC::Test (from the testsuite of DBIx::Class::InflateColumn::Currency)

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2007 by Nathan Gray

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.

=cut

