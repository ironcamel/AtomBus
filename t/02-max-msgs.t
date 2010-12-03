use Test::More tests => 5;
use AtomMQ;
use AtomMQ::Schema;
use DBI;
use Test::MockObject::Extends;
use XML::XPath;

# Set up db.
my $dbh = DBI->connect('dbi:SQLite:dbname=:memory:');
my $schema = AtomMQ::Schema->connect(sub { $dbh });
$schema->deploy;
my $ftitle = 'feed1';
$schema->resultset('AtomMQFeed')->create(
    { title => $ftitle, id => 1, author_name => 'a', updated => 1 });
my @entries = map 
    {feed_title => $ftitle, id => $_, title => $_, content => $_, updated => 1},
    1 .. 10;
$schema->resultset('AtomMQEntry')->create($_) foreach @entries;

my $atommq = AtomMQ->new(schema => $schema);
$atommq = Test::MockObject::Extends->new($atommq);
$atommq->set_always(request_method => 'GET');

my $xml = $atommq->get_feed($ftitle);
my $xp = XML::XPath->new(xml => $xml);
my $nodeset = $xp->find('/feed/entry/id');
is $nodeset->get_nodelist => 10, "Got all messages";

$atommq = AtomMQ->new(schema => $schema, max_msgs_per_request => 6);
$atommq = Test::MockObject::Extends->new($atommq);
$atommq->set_always(request_method => 'GET');

$xml = $atommq->get_feed($ftitle);
$xp = XML::XPath->new(xml => $xml);
$nodeset = $xp->find('/feed/entry/id');
is $nodeset->get_nodelist => 6, "Got 6 messages";
is_deeply [ map $_->string_value, $nodeset->get_nodelist ] => [ 1 .. 6 ],
    'Got messages 1 - 6';

$atommq = AtomMQ->new(schema => $schema, max_msgs_per_request => 6);
$atommq = Test::MockObject::Extends->new($atommq);
$atommq->set_always(request_method => 'GET');
$atommq->set_always(request_header => 6); #set Xlastid to 6

$xml = $atommq->get_feed($ftitle);
$xp = XML::XPath->new(xml => $xml);
$nodeset = $xp->find('/feed/entry/id');
is $nodeset->get_nodelist => 4, "Got rest of the messages";
is_deeply [ map $_->string_value, $nodeset->get_nodelist ] => [ 7 .. 10 ],
    'Got messages 7 - 10';

