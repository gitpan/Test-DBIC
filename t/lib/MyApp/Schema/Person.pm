package MyApp::Schema::Person;

use strict;
use warnings;

use base 'DBIx::Class';
__PACKAGE__->load_components('Core');
__PACKAGE__->table('person');
__PACKAGE__->add_columns(
    'id' => {
        'data_type' => 'NUMBER',
        'default_value' => q{},
        'is_nullable' => 'N',
        'size' => '22',
    },
    'first_name' => {
        'data_type' => 'VARCHAR2',
        'default_value' => q{},
        'is_nullable' => 'Y',
        'size' => '50',
    },
    'last_name' => {
        'data_type' => 'VARCHAR2',
        'default_value' => q{},
        'is_nullable' => 'Y',
        'size' => '50',
    },
);

__PACKAGE__->set_primary_key(qw/id/);

1;
