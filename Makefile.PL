# Load the Module::Install bundled in ./inc/
use inc::Module::Install;

# Define metadata
name 'Test-DBIC';
license 'perl';
perl_version '5.006001';
all_from 'lib/Test/DBIC.pm';

# files to remove
clean_files 't/var/test.db*';

# Specific dependencies
requires 'DBIx::Class'              => 0.07005;
requires 'Class::Accessor::Grouped' => '0.03';

build_requires 'DBD::SQLite'              => '1.11';
build_requires 'Test::More'               => '0.42';
build_requires 'Test::Builder::Module'    => 0;
build_requires 'Class::Accessor::Grouped' => 0;
build_requires 'File::Spec::Functions'    => 0;

#recommends      'Your::OtherModule' => '0.01';

auto_install;
WriteAll;

