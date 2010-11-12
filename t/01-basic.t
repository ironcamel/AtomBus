use Test::More;
use Test::Exception;
use AtomMQ;

throws_ok { AtomMQ->new(feed => 'x', dsn => 'dbi:foodb:asdf') }
    qr/The database foodb is not supported/,
    'correct exception for unsupported db';

done_testing;
