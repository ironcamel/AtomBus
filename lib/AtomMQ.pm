package AtomMQ;
use Moose;
use MooseX::NonMoose;
extends 'Atompub::Server';

use AtomMQ::Schema;
use Capture::Tiny qw(capture);
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
has auto_create_db => (
    is => 'ro',
    isa => 'Bool',
    default => 1,
);

sub BUILD {
    my $self = shift;
    # Automagically create db table.
    capture { eval { $self->schema->deploy } } if $self->auto_create_db;
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

1;

# ABSTRACT: An atompub server that supports the message queue/bus model.

=head1 SYNOPSIS

    #!/usr/bin/perl
    use AtomMQ;
    my $dsn = 'dbi:SQLite:dbname=/path/to/foo.db';
    my $server = AtomMQ->new(feed => 'MyCoolFeed', dsn => $dsn);
    $server->run;

=head1 DESCRIPTION

AtomMQ is an atompub server that supports the message queue/bus model.
Throughout this document, I will use the term message when refering to an atom
feed entry, since the point of this module is to use atompub for messaging.
AtomMQ extends Inoue's L<Atompub::Server> which extends Miyagawa's
L<XML::Atom::Server>.
Can you feel the love already?

To get started, just copy the code from the L</SYNOPSIS> to a file.
You now have a shiny new atompub server with a feed named MyCoolFeed.
You can configure your web server to run it via CGI or as a mod_perl handler.
My recommendation is to run it in a L<PSGI> environment.
See the L</PSGI> section for directions.
To create more feeds, just copy that file and change 'MyCoolFeed' to
'MyOtherFeed'.

To publish a message to AtomMQ, make a HTTP POST request:

    $ curl -d '<entry> <title>allo</title> <content type="xhtml">
      <div xmlns="http://www.w3.org/1999/xhtml" >an important message</div>
      </content> </entry>' http://localhost/cgi-bin/mycoolfeed

To retrieve messages, make a HTTP GET request:

    $ curl http://localhost/cgi-bin/mycoolfeed

That will get all the messages since the feed was created.
Lets say you are running a client that polls the feed and processes messages.
If this client dies, you will not want it to process all the messages again when
it comes back up.
So clients are responsible for maintaining and persisting the id of the last
message they processed.
This allows a client to request only messages that came after the message with
the given id.
They can do this by passing a Xlastid header:

    $ curl -H 'Xlastid: 42' http://localhost/cgi-bin/mycoolfeed

That will return only messages that came after the message that had id 42.

=method new

Arguments: $feed, $dsn, $user, $password, $auto_create_db

This is the AtomMQ constructor. The required arguments are $feed and $dsn.
$feed is the name of the feed.
$dsn should be a valid L<DBI> dsn.
$user and $password are optional and should be provided if your database
requires them.
$auto_create_db defaults to 1.
Set it to 0 if you don't want AtomMQ to attempt to create the db table for you.
You can leave it set to 1 even if the db table already exists.
Setting it to 0 improves performance slightly.
See L</DATABASE> for more info.

    my $server = AtomMQ->new(feed => 'MyCoolFeed', dsn => $dsn);

=method run

Arguments: None

Call this method to start the server.

=head1 DATABASE

AtomMQ depends on a database to store its data.
The dsn you pass to the constructor must point to a database which you have
write privileges to.
Only one table named atommq_entry is required.
This table will be created automagically for you if it doesn't already exist.
Of course for that to work, you will need create table privileges.
You can also create the table yourself if you like.
Here is an example sql command for creating the table in sqlite:

    CREATE TABLE atommq_entry (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        feed VARCHAR(255) NOT NULL,
        title VARCHAR(255) NOT NULL,
        content TEXT NOT NULL
    );

The feed, title and content columns can be of type TEXT or VARCHAR and can
be any size you want.
All databases supported by L<DBIx::Class> are supported,
which are most major databases including postgresql, sqlite, mysql and oracle.

=head1 PSGI

If you have the need for speed, then this section is for you.
AtomMQ can be run in a persistent L<PSGI> environment via L<Plack>.
This is the recommended way to run AtomMQ, but it takes slightly more work.
You will need to have L<Plack> and L<CGI::Emulate::PSGI> installed.
Copy the following to mycoolfeed.fcgi:

    #!/usr/bin/perl
    use AtomMQ;
    use CGI::Emulate::PSGI;
    my $app = CGI::Emulate::PSGI->handler(sub {
        my $dsn = 'dbi:SQLite:dbname=/path/to/foo.db';
        my $server = AtomMQ->new(feed => 'MyCoolFeed', dsn => $dsn);
        $server->run
    });

Then you can run:

    plackup -p 5000 mycoolfeed.fcgi

Now AtomMQ is running on port 5000 via the L<HTTP::Server::PSGI> web server.
If you want to run in a FastCGI environment using your favorite web server,
then you can run:

    plackup -s FCGI --listen /tmp/fcgi.sock mycoolfeed.fcgi

Then configure your web server accordingly. Here is an example lighttpd
configuration:

    fastcgi.server += (
        ".fcgi" => ((  "socket" => "/tmp/fcgi.sock" ))
    )

=head1 MOTIVATION

I am a big fan of messaging systems because they make it so easy to create
scalable systems.
Existing message brokers are great for creating message queues.
But once a consumer reads a message off of a queue, it is gone.
I needed a system to publish events such that multiple heterogeneous services
could subscribe to them.
So I really needed a message bus, not a message queue.
I know for example I could have used something called topics in ActiveMQ,
but they are extremely flakey in my experience.
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
