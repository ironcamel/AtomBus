package AtomMQ;
use Moose;
use MooseX::NonMoose;
extends 'Atompub::Server';

use AtomMQ::Schema;
use Atompub::DateTime qw(datetime);
use Capture::Tiny qw(capture);
#use DateTime;
use Data::Dumper;
use UUID::Tiny;
use XML::Atom;
$XML::Atom::DefaultVersion = '1.0';
use XML::Atom::Person;

# VERSION

has db_info => (
    is => 'ro',
    isa => 'HashRef[Str]',
);
has schema => (
    is => 'ro',
    isa => 'AtomMQ::Schema',
    lazy_build => 1,
);
has auto_create_db => (
    is => 'ro',
    isa => 'Bool',
    default => 1,
);

sub _build_schema {
    my $self = shift;
    my $db_info = $self->db_info;
    $db_info = { %$db_info, AutoCommit => 1, RaiseError => 1 };
    return AtomMQ::Schema->connect($db_info);
}

sub BUILD {
    my $self = shift;
    die "The AtomMQ constructor requires a db_info or schema parameter."
        unless $self->db_info or $self->has_schema;
    # Automagically create db table.
    $self->schema->deploy if $self->auto_create_db;
    #capture { eval { $self->schema->deploy } } if $self->auto_create_db;
}

sub handle_request {
    my $self = shift;
    $self->response_content_type('application/xml');
    my $method = $self->request_method || 'METHOD IS MISSING';
    my %dispatch = (
        GET  => 'get_feed',
        POST => 'new_post',
    );
    my $handler = $dispatch{$method};
    die "HTTP method [$method] is not supported\n" unless $handler;
    my $feed_name = $self->request_param('feed');
    die 'A feed param is required in the uri, e.g., /atommq/feed=widgets'
        unless defined $feed_name and $feed_name ne '';
    $self->$handler($feed_name);
}

sub get_feed {
    my ($self, $feed_title) = @_;
    $feed_title = lc $feed_title;
    my $last_id = $self->request_header('Xlastid') || 0;
    my $order_id;
    my $schema = $self->schema;
    if ($last_id) {
        my $entry = $schema->resultset('AtomMQEntry')->find({id => $last_id});
        if (not $entry) {
            $self->response_code(400);
            return "No such entry exists with id $last_id";
        }
        $order_id = $entry->order_id;
    }

    my $db_feed = $self->schema->resultset('AtomMQFeed')->find(
        { title => $feed_title });
    if (not $db_feed) {
        $self->response_code(404);
        return "No such feed exists named $feed_title";
    }

    my $feed = XML::Atom::Feed->new;
    $feed->title($feed_title);
    $feed->id($db_feed->id);
    my $person = XML::Atom::Person->new;
    $person->name($db_feed->author_name);
    $feed->author($person);
    $feed->updated($db_feed->updated);

    my %query = (feed_title => $feed_title);
    $query{order_id} = { '>' => $order_id } if $order_id;
    my $rset = $self->schema->resultset('AtomMQEntry')->search(
        \%query, { order_by => ['order_id'] });
    while (my $entry = $rset->next) {
        $feed->add_entry(_entry_from_db($entry));
    }

    return $feed->as_xml;
}

sub new_post {
    my ($self, $feed_title) = @_;
    $feed_title = lc $feed_title;
    my $entry = $self->atom_body;
    if (not $entry) {
        $self->response_code(400);
        return "Atom content is missing";
    }
    my $updated = datetime->w3cz;
    my $db_feed = $self->schema->resultset('AtomMQFeed')->find_or_create({
        title       => $feed_title,
        id          => _gen_id(),
        author_name => 'AtomMQ',
        updated     => $updated,
    }, { key => 'title_unique' });
    my $db_entry = $self->schema->resultset('AtomMQEntry')->create({
        feed_title => $feed_title,
        id         => _gen_id(),
        title      => $entry->title,
        content    => $entry->content->body,
        updated    => $updated,
    });
    $db_feed->update({updated => $updated});
    return _entry_from_db($db_entry)->as_xml;
}

sub _gen_id { 'urn:uuid:' . create_UUID_as_string() }

sub _entry_from_db {
    my $row = shift;
    my $entry = XML::Atom::Entry->new;
    $entry->title($row->title);
    $entry->content($row->content);
    $entry->id($row->id);
    $entry->updated($row->updated);
    return $entry;
}

# ABSTRACT: An atompub server that supports the message queue/bus model.

=head1 SYNOPSIS

    #!/usr/bin/perl
    use AtomMQ;
    my $db_info = { dsn => 'dbi:SQLite:dbname=/path/to/foo.db' };
    my $server = AtomMQ->new(db_info => $db_info);
    $server->run;

=head1 DESCRIPTION

AtomMQ is an atompub server that supports the message queue/bus model.
Throughout this document, I will use the term message when referring to an atom
feed entry, since the point of this module is to use atompub for messaging.
The idea is that atom feeds correspond to conceptual queues (or buses) and atom
entries correspond to messages.
AtomMQ extends Inoue's L<Atompub::Server> which extends Miyagawa's
L<XML::Atom::Server>.
Can you feel the love already?

To create an AtomMQ server, just copy the code from the L</SYNOPSIS>.
Make sure to change the dsn to something valid and chmod +x the file.
Right away you can run it via CGI or as a mod_perl handler.
To run in a FastCGI or L<PSGI> environment, see the L</FastCGI> and L</PSGI>
sections in this document.
This is highly recommended because it will run considerably faster.

These examples assume that you have configured your web server to point http
requests starting with /atommq to the script you just created.
To publish a message, make a HTTP POST request:

    $ curl -d '<entry> <title>allo</title> <content type="xhtml">
      <div xmlns="http://www.w3.org/1999/xhtml" >an important message</div>
      </content> </entry>' http://localhost/atommq/feed=widgets

That adds a new message to a feed titled widgets.
If that feed didn't exist before, it will be created for you.
To retrieve messages from the widgets feed, make a HTTP GET request:

    $ curl http://localhost/atommq/feed=widgets

That will get all the messages since the feed was created.
Lets say you are running a client that polls the feed and processes messages.
If this client dies, you will not want it to process all the messages again when
it comes back up.
So clients are responsible for maintaining and persisting the id of the last
message they processed.
This allows a client to request only messages that came after the message with
the given id.
They can do this by passing a Xlastid header:

    $ curl -H 'Xlastid: urn:uuid:4018425e-f747-11df-b990-b7043ee4d39e' http://localhost/atommq/feed=widgets

=method new

Arguments: \%db_info [, $auto_create_db]

This is the AtomMQ constructor. Only $db_info is required.
$db_info is a hashref containing the database connection info as described
in L<DBIx::Class::Storage::DBI/connect_info>.
It must at least contain a dsn entry.
$auto_create_db defaults to 1.
Set it to 0 if you don't want AtomMQ to attempt to create the db table for you.
You can leave it set to 1 even if the db table already exists.
Setting it to 0 improves performance slightly.
See L</DATABASE> for more info. Example:

    my $server = AtomMQ->new(auto_create_db => 0,
        db_info => {
            dsn      => 'dbi:SQLite:dbname=/path/to/foo.db',
            user     => 'joe',
            password => 'momma',
        }
    );

=method run

Arguments: None

Call this method to start the server.

=head1 DATABASE

AtomMQ uses a database to store its data.
The db_info you pass to the constructor must point to a database which you have
write privileges to.
The tables will be created automagically for you if they don't already exist.
Of course for that to work, you will need create table privileges.
All databases supported by L<DBIx::Class> are supported,
which are most major databases including postgresql, sqlite, mysql and oracle.

=head1 FastCGI

CGI can be very slow. Not to worry, AtomMQ can be run via FastCGI.
This requires that you have the L<FCGI> module installed.

    #!/usr/bin/perl
    use AtomMQ;
    use FCGI;

    my $db_info = { dsn => "dbi:SQLite:dbname=/path/to/foo.db" };
    my $request = FCGI::Request();
    while($request->Accept() >= 0) {
        my $server = AtomMQ->new(db_info => $db_info);
        $server->run;
    }

Here is an example lighttpd config.
It assumes you named the above file atommq.fcgi.
Make sure you chmod +x atommq.fcgi.

    fastcgi.server += (
        "/atommq" => ((
            "socket" => "/tmp/fcgi.sock",
            "check-local" => "disable",
            "bin-path" => "/path/to/atommq.fcgi",
        )),
    )

Now AtomMQ will be running via FastCGI under /atommq.

=head1 PSGI

AtomMQ can also be run in a L<PSGI> environment via L<Plack>.
Here is one way to do it.
You will need to have L<Plack>, L<CGI::Emulate::PSGI> and L<CGI::Compile>
installed for this example.
Copy the following to atommq.psgi.

    use Plack::App::WrapCGI;
    my $app = Plack::App::WrapCGI->new(script => "/path/to/atommq.cgi")->to_app;

The "/path/to/atommq.cgi" string should be changed to the path to a cgi script
such as the one in the L</SYNOPSIS>.
Then you can for example run:

    plackup -p 5000 atommq.psgi

Now AtomMQ is running on port 5000 via the L<HTTP::Server::PSGI> web server.
Of course you can use any PSGI/Plack web server via the -s option to plackup.

=head1 MOTIVATION

I like messaging systems because they make it so easy to create scalable applications.
Existing message brokers are great for creating message queues.
But once a consumer reads a message off of a queue, it is gone.
I needed a system to publish events such that multiple heterogeneous services
could subscribe to them.
So I really needed a message bus, not a message queue.
I could for example have used something called topics in ActiveMQ,
but I have found them to have issues with persistence.
Actually, I have found ActiveMQ to be broken in general.
An instance I manage has to be restarted at least twice a week.
AtomMQ on the other hand will be extremely stable, because it is so simple.
It is in essence just an interface to a database.
As long as your database and web server are up, AtomMQ will be there for you.
She will not let you down.
And there are all sorts of ways to add redundancy to databases and web heads.
Another advantage of using AtomMQ is that atompub is an RFC standard.
Everyone already has a client for it, their browser.
Aren't standards great!  
By the way, if you just need message queues, try
L<POE::Component::MessageQueue>.
It rocks. If you need a message bus, give AtomMQ a shot.

=cut

1;
