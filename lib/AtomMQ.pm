package AtomMQ;
use Moose;
use MooseX::NonMoose;
extends 'Atompub::Server';

use AtomMQ::Schema;
use Data::Dumper;
use XML::Atom;
$XML::Atom::DefaultVersion = '1.0';

# VERSION

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
has user => (
    is => 'ro',
    isa => 'Str',
);
has password => (
    is => 'ro',
    isa => 'Str',
);
has schema => (
    is => 'ro',
    isa => 'AtomMQ::Schema',
    lazy => 1,
    default => sub {
        my $self = shift;
        AtomMQ::Schema->connect($self->dsn, $self->user, $self->password,
            { RaiseError => 1, AutoCommit => 1 });
    }
);

sub BUILD {
    my $self = shift;
    $self->schema->deploy;
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
    my $feed_name = $self->feed;
    #my $p = $self->request_param('start-index');
    my $last_id = $self->request_header('Xlastid') || 0;
    my $feed = XML::Atom::Feed->new;
    $feed->title($feed_name);
    my $rset = $self->schema->resultset('AtomMQEntry')->search({
        id   => { '>' => $last_id },
        feed => $feed_name,
    });
    while (my $row = $rset->next) {
        my $entry = XML::Atom::Entry->new;
        $entry->title($row->title);
        $entry->content($row->content);
        $entry->id($row->id);
        $feed->add_entry($entry);
    }
    return $feed->as_xml;
}

sub new_post {
    my $self = shift;
    my $entry = $self->atom_body or return;
    $self->schema->resultset('AtomMQEntry')->create({
        feed    => $self->feed,
        title   => $entry->title,
        content => $entry->content->body,
    });
}

# ABSTRACT: An atompub server that supports the message queue/bus model.

=head1 SYNOPSIS

    #!/usr/bin/perl
    use AtomMQ;
    my $dsn = 'dbi:SQLite:dbname=foo.db';
    my $server = AtomMQ->new(feed => 'MyCoolFeed', dsn => $dsn);
    $server->run;

=head1 DESCRIPTION

An atompub server that supports the message queue/bus model.  Throughout this
document, I will use the term message when refering to an atom feed entry, since
the point of this module is to use atompub for messaging purposes.  AtomMQ
extends Inoue's Atompub::Server which extends Miyagawa's XML::Atom::Server.  Can
you feel the love already?

Usage:

    #!/usr/bin/perl
    use AtomMQ;
    my $dsn = 'dbi:SQLite:dbname=foo.db';
    my $server = AtomMQ->new(feed => 'MyCoolFeed', dsn => $dsn);
    $server->run;

Just drop the above file in your cgi-bin folder on your web server, and you will
have a shiny new atompub server with a feed titled MyCoolFeed.  It can also be
run via mod_perl on apache, but that is more complicated.  To create more
feeds, just copy that file and change 'MyCoolFeed' to 'MyOtherFeed'.

To publish a message to AtomMQ, make a HTTP POST request:

    $ curl -d '<entry> <title>allo</title> <content type="xhtml">
      <div xmlns="http://www.w3.org/1999/xhtml" >an important message</div>
      </content> </entry>' http://localhost/cgi-bin/mycoolfeed

Where mycoolfeed is the name of the file you created in cgi-bin.

So how is this different than a regular atompub server?  Just one simple thing.
A concept of lastid.  So if you just do:

    $ curl http://localhost/cgi-bin/mycoolfeed

you will get all messages since the feed was created. But lets say you are
running a client that polls the feed and processes messages.  If this client
dies, you will not want it to process all the messages again.  So clients are
responsible for maintaining and persisting the id of the last message they
processed.  This allows a client to request only messages that came after
the message with the given id.  They can do this by passing a Xlastid header:

    $ curl -H 'Xlastid: 42' http://localhost/cgi-bin/mycoolfeed

That will return only messages that came after the message that had id 42.

=cut

1;
