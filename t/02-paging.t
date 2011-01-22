use Test::More import => ['!pass'], tests => 17;
use Dancer qw(:syntax);
use Dancer::Test;

use XML::XPath;
use Dancer::Plugin::DBIC qw(schema);
use AtomBus;
use Capture::Tiny qw(capture);

set atombus => {
    db => {
        dsn => 'dbi:SQLite:dbname=:memory:',
    }
};

my $xml = q{
    <entry>
        <title>title%s</title>
        <content type="xhtml">
            <div xmlns="http://www.w3.org/1999/xhtml">content%s</div>
        </content>
    </entry>
};

# Confirm that feed doesn't exist yet.
capture { # Silence output from schema->deploy in before filter.
    response_status_is [ GET => "/feeds/foo" ], 404;
};

foreach my $i (1 .. 10) {
    dancer_response POST => "/feeds/foo", { body => sprintf($xml, $i, $i) };
}
my $res = dancer_response GET => "/feeds/foo";
my $xp = XML::XPath->new(xml => $res->{content});
my @entries = $xp->findnodes('/feed/entry');
is $res->{status}=> 200, 'Status was 200';
is @entries => 10, 'There are 10 entries';
is_deeply
    [ map $_->findvalue('./content/div'), @entries ],
    [ map "content$_", 1 .. 10 ],
    "All 10 entries are in order.";

my $id = $entries[4]->find('./id'); # this is the 5th entry
$res = dancer_response GET => "/feeds/foo", { params => { start_at => $id } };
$xp = XML::XPath->new(xml => $res->{content});
@entries = $xp->findnodes('/feed/entry');
is @entries => 6, 'Got 6 entries when starting at the 5th one.';
is_deeply
    [ map $_->findvalue('./content/div'), @entries ],
    [ map "content$_", 5 .. 10 ],
    "All 6 entries are in order.";

$res = dancer_response GET => "/feeds/foo", { params => {start_after => $id} };
$xp = XML::XPath->new(xml => $res->{content});
@entries = $xp->findnodes('/feed/entry');
is @entries => 5, 'Got 5 entries when starting after the 5th one.';
is_deeply
    [ map $_->findvalue('./content/div'), @entries ],
    [ map "content$_", 6 .. 10 ],
    "All 5 entries are in order.";

$res = dancer_response GET => "/feeds/foo",
    { headers => [ 'If-None-Match' => $id ] };
$xp = XML::XPath->new(xml => $res->{content});
@entries = $xp->findnodes('/feed/entry');
is @entries => 5, 'Got 5 entries when If-None-Match is 5th element.';
is_deeply
    [ map $_->findvalue('./content/div'), @entries ],
    [ map "content$_", 6 .. 10 ],
    "All 5 entries are in order.";

$res = dancer_response GET => "/feeds/foo",
    { headers => [ 'If-None-Match' => 'foo' ] };
$xp = XML::XPath->new(xml => $res->{content});
@entries = $xp->findnodes('/feed/entry');
is @entries => 10, 'Got all entries when If-None-Match is an unkown id.';

$id = $entries[-1]->find('./id'); # this is the last entry
$res = dancer_response GET => "/feeds/foo",
    { headers => [ 'If-None-Match' => $id] };
is $res->{status}, 304, "Status is 304 when If-None-Match is the last id";
is $res->{content}, '', "Body is empty when If-None-Match is the last id";

config->{atombus}{page_size} = 7;

$res = dancer_response GET => "/feeds/foo";
$xp = XML::XPath->new(xml => $res->{content});
@entries = $xp->findnodes('/feed/entry');
is @entries => 7, 'There are 7 entries with page_size = 7.';
is_deeply
    [ map $_->findvalue('./content/div'), @entries ],
    [ map "content$_", 1 .. 7 ],
    "All 7 entries are in order.";

$id = $entries[-1]->find('./id');
$res = dancer_response GET => "/feeds/foo", { params => {start_after => $id} };
$xp = XML::XPath->new(xml => $res->{content});
@entries = $xp->findnodes('/feed/entry');
is @entries => 3, 'Got rest of entries on last (second) page.';
is_deeply
    [ map $_->findvalue('./content/div'), @entries ],
    [ map "content$_", 8 .. 10 ],
    "All 3 entries are in order.";

done_testing;
