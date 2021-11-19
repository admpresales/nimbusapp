requires 'File::Slurp';
requires 'HTTP::Tiny';
requires 'YAML::Tiny';
requires 'JSON::Tiny';
requires 'Template::Tiny';
requires 'Sort::Versions';

recommends 'IO::Socket::SSL';
recommends 'Net::SSLeay';

test_requires 'IO::Socket::SSL';
test_requires 'Net::SSLeay';

build_requires 'App::FatPacker';