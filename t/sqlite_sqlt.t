#!perl -wT
use strict;
use warnings;

BEGIN {
    use lib 't/lib';
    use Test::DBIC;

    my %missing;
    eval 'require DBD::SQLite';
    $missing{'DBD::SQLite'}++ if $@;
    eval 'require SQL::Translator';
    $missing{'SQL::Translator'}++ if $@;
    if (keys %missing) {
        plan skip_all => 'dependencies not installed: ' . join(', ', sort keys %missing);
    } else {
        plan tests => 6;
    }
};

my $schema = Test::DBIC->init_schema(
    sqlt_deploy => 1,
    existing_namespace => 'MyApp::Schema',
    sample_data_file => 't/var/sample_data.txt',
    sample_data => [
        'Person' => [
            ['id', 'first_name', 'last_name'],
            [200, 'John', 'Doe'],
            [300, 'Jane', 'Doe'],
        ],
    ],
);

{
    my $people = $schema->resultset('Person')->search;
    is($people->count, 3);

    my $person = $people->next;
    is($person->id, 100);
    $person = $people->next;
    is($person->id, 200);
    $person = $people->next;
    is($person->id, 300);
}

{
    my $bar = $schema->resultset('Bar')->search;
    is($bar->count, 1);

    my $record = $bar->next;
    is($record->id, 2);
}

