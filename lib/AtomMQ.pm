package AtomMQ;
use Moose;
use MooseX::NonMoose;
extends 'Atompub::Server';

use Data::Dumper;
use DBI;
use XML::Atom;
$XML::Atom::DefaultVersion = '1.0';

has feed => (
    is => 'ro',
    isa => 'Str',
    required => 1,
);
has dsn => (
    is => 'ro',
    isa => 'Str',
    required => 1,
);
has username => (
    is => 'ro',
    isa => 'Str',
);
has password => (
    is => 'ro',
    isa => 'Str',
);
has dbh => (
    is => 'ro',
    isa => 'DBI::db',
    lazy => 1,
    default => sub {
        my $self = shift;
        DBI->connect($self->dsn, $self->username, $self->password,
            { RaiseError => 1, AutoCommit => 1 });
    }
);

my $ENTRY_TABLE = 'atommq_entry';
#$ENTRY_TABLE = 'foo';

sub BUILD {
    my $self = shift;
    my $dbh = $self->dbh;
    my $dsn = $self->dsn;

    my $db_type = (split /:/, $self->dsn)[1];
    die "invalid dsn [$dsn]" unless $db_type;
    $db_type = lc $db_type;

    my %auto_inc = (
        sqlite => 'AUTOINCREMENT',
        mysql  => 'AUTO_INCREMENT',
    );
    my $auto_inc = $auto_inc{$db_type};
    die "The database $db_type is not supported. Currently, the only supported"
        . " databases are [ @{[join ', ', keys %auto_inc]} ]"
        unless $auto_inc;

    $self->dbh->do(qq{
        CREATE TABLE IF NOT EXISTS $ENTRY_TABLE (
            id INTEGER PRIMARY KEY $auto_inc,
            feed VARCHAR(255) NOT NULL,
            title VARCHAR(255) NOT NULL,
            content TEXT NOT NULL
        )
    });
}

my %dispatch = (
    GET  => 'get_feed',
    POST => 'new_post',
);

sub handle_request {
    my $self = shift;
    $self->response_content_type('text/plain');
    $self->response_content_type('text/xml');
    my $method = $self->request_method || 'METHOD IS MISSING';
    my $handler = $dispatch{$method};
    die "HTTP method [$method] is not supported\n" unless $handler;
    $self->$handler();
}

sub get_feed {
    my $self = shift;
    my $dbh = $self->dbh;
    my $feed_name = $self->feed;
    #my $p = $self->request_param('start-index');
    my $last_id = $self->request_header('Xlastid') || 0;
    my $feed = XML::Atom::Feed->new;
    $feed->title($feed_name);
    my $sql = "select * from $ENTRY_TABLE where feed = ? and id > ?";
    my $rows = $dbh->selectall_arrayref($sql, {Slice => {}},
        $feed_name, $last_id);
    for my $row (@$rows) {
        my $entry = XML::Atom::Entry->new;
        $entry->title($row->{title});
        $entry->content($row->{content});
        $entry->id($row->{id});
        $feed->add_entry($entry);
    }

    return $feed->as_xml;
}

sub new_post {
    my $self = shift;
    my $dbh = $self->dbh;
    my $entry = $self->atom_body or return;
    $dbh->do("insert into $ENTRY_TABLE (feed, title, content) values (?,?,?)",
        {}, $self->feed, $entry->title, $entry->content->body);
    #return Dumper $dbh->selectall_arrayref("select * from $ENTRY_TABLE");
}

