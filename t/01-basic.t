use Test::More tests => 6;
use AtomMQ;
use Test::Exception;
use Test::MockObject;
use Test::MockObject::Extends;

my $feed = 'foo_feed';
my $title = 'title1';
my $content = 'content1';

my $server = AtomMQ->new(db_info => { dsn => 'dbi:SQLite:dbname=:memory:' });
ok $server, 'Created AtomMQ server.';

my $mock_content = Test::MockObject->new();
$mock_content->set_bound(body => \$content);

my $mock_atom_body = Test::MockObject->new();
$mock_atom_body->set_bound(title => \$title);
$mock_atom_body->set_always(content => $mock_content);

$server = Test::MockObject::Extends->new($server);
$server->set_always(atom_body => $mock_atom_body);
$server->set_always(request_method => 'POST');
$server->new_post($feed);

my $schema = $server->schema;
my ($entry1) = $schema->resultset('AtomMQEntry')->search(
    { title => $title, content => $content, feed_title => $feed });
ok $entry1, 'Found entry 1.';

$content = 'content2';
$title = 'title2';
$server->new_post($feed);

my ($entry2) = $schema->resultset('AtomMQEntry')->search(
    { title => $title, content => $content, feed_title => $feed });
ok $entry2, 'Found entry 2.';

ok $entry2->order_id > $entry1->order_id, 'order_id field got incremented.';

is $schema->resultset('AtomMQEntry')->count => 2, 'There are 2 entries';

throws_ok { AtomMQ->new(feed => $feed) } qr/requires.+db_info.+or.+schema/,
    'Correct exception for missing db_info';
