package Test::DBIC::Schema;
use strict;
use warnings;

our $VERSION = '0.01001';

BEGIN {
    use base qw/DBIx::Class::Schema/;
};
__PACKAGE__->load_classes;

sub dsn {
    return shift->storage->connect_info->[0];
};

1;
