package AtomMQ;
use Dancer qw(:syntax);
use Dancer::Plugin::DBIC qw(schema);

use Atompub::DateTime qw(datetime);
use Capture::Tiny qw(capture);
use UUID::Tiny;
use XML::Atom;
$XML::Atom::DefaultVersion = '1.0';
use XML::Atom::Person;

# VERSION

my $deployed = 0;
before sub {
    # Automagically create db if it doesn't exist.
    return if $deployed;
    capture { schema->deploy };
    $deployed = 1;
};

get '/feeds/:feed_title' => sub {
    my $feed_title = lc params->{feed_title};
    my $start_after = params->{start_after};
    my $start_at = params->{start_at};
    my $order_id;

    if ($start_after) {
        my $entry = schema->resultset('AtomMQEntry')->find(
            {id => $start_after});
        return send_error("No such message exists with id $start_after", 400)
            unless $entry;
        $order_id = $entry->order_id;
    }

    if ($start_at) {
        my $entry = schema->resultset('AtomMQEntry')->find(
            {id => $start_at});
        return send_error("No such message exists with id $start_at", 400)
            unless $entry;
        $order_id = $entry->order_id;
    }

    my $db_feed = schema->resultset('AtomMQFeed')->find(
        { title => $feed_title });
    return send_error("No such feed exists named $feed_title", 404)
        unless $db_feed;

    my $feed = XML::Atom::Feed->new;
    $feed->title($feed_title);
    $feed->id($db_feed->id);
    my $person = XML::Atom::Person->new;
    $person->name($db_feed->author_name);
    $feed->author($person);
    $feed->updated($db_feed->updated);

    my %query = (feed_title => $feed_title);
    $query{order_id} = { '>' => $order_id } if $order_id;
    my $rset = schema->resultset('AtomMQEntry')->search(
        \%query, { order_by => ['order_id'] });
    my $count = -1;
    while ($count-- && (my $entry = $rset->next)) {
        $feed->add_entry(entry_from_db($entry));
    }

    return $feed->as_xml;
};

post '/feeds/:feed_title' => sub {
    my $feed_title = lc params->{feed_title};
    my $body = request->body;
    return send_error("Request body is empty", 400)
        unless $body;
    my $entry = XML::Atom::Entry->new(\$body);
    my $updated = datetime->w3cz;
    my $db_feed = schema->resultset('AtomMQFeed')->find_or_create({
        title       => $feed_title,
        id          => gen_id(),
        author_name => 'AtomMQ',
        updated     => $updated,
    }, { key => 'title_unique' });
    my $db_entry = schema->resultset('AtomMQEntry')->create({
        feed_title => $feed_title,
        id         => gen_id(),
        title      => $entry->title,
        content    => $entry->content->body,
        updated    => $updated,
    });
    $db_feed->update({updated => $updated});
    return entry_from_db($db_entry)->as_xml;
};

sub gen_id { 'urn:uuid:' . create_UUID_as_string() }

sub entry_from_db {
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

    use Dancer;
    use AtomMQ;
    dance;

=head1 DESCRIPTION

AtomMQ is an atompub server that supports the message queue/bus model.
Throughout this document, I will use the term message when referring to an atom
feed entry, since the point of this module is to use atompub for messaging.
The idea is that atom feeds correspond to conceptual queues (or buses) and atom
entries correspond to messages.
AtomMQ is built on top of the L<Dancer>, L<XML::Atom> and L<Atompub> frameworks.
Since AtomMQ is a L<PSGI> application, deployment is very flexible.
It can be run on any web server of your choice in any environment, such as
PSGI, CGI or FastCGI.

These examples assume that you have configured your web server to point http
requests starting with /atommq to AtomMQ.
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
They can do this by providing the start_after parameter:

    $ curl -H http://localhost/atommq/feed=widgets?start_after=urn:uuid:4018425e-f747-11df-b990-b7043ee4d39e

Alternatively, you can provide a start_at param.  This will retrieve messages
starting at the message with the given id:

    $ curl -H http://localhost/atommq/feed=widgets?start_at=urn:uuid:4018425e-f747-11df-b990-b7043ee4d39e

=head1 CONFIGURATION

Configuration can be achieved via a config.yml file or via the set keyword.
To use the config.yml approach, you will need to install L<YAML>.
See the L<Dancer> documentation for more information.

Example config.yml:

    logger: file
    log: errors
    plugins:
        DBIC:
            atommq:
                schema_class: "AtomMQ::Schema"
                dsn: "dbi:mysql:database=atommq"
                user: joe
                password: momma

You can alternatively configure the server via the set keyword:

    use Dancer;
    use AtomMQ;

    set logger => 'file';
    set log => 'debug';
    set show_errors => 1;
    set plugins => {
        DBIC => {
            atommq => {
                schema_class => 'AtomMQ::Schema',
                dsn => 'dbi:SQLite:dbname=/var/local/atommq/atommq.db',
            }
        }
    };

    dance;

=head1 DATABASE

AtomMQ uses a database to store its data.
The dsn in the config must point to a database which you have write privileges
to.
The tables will be created automagically for you if they don't already exist.
Of course for that to work, you will need create table privileges.
All databases supported by L<DBIx::Class> are supported,
which are most major databases including postgresql, sqlite, mysql and oracle.

=head1 FastCGI

AtomMQ can be run via FastCGI.
This requires that you have the L<FCGI> module installed.
Here is an example dispatch.fcgi:

    #!/usr/bin/env perl
    use Dancer ':syntax';
    use FindBin '$RealBin';
    use Plack::Handler::FCGI;

    set apphandler => 'PSGI';
    set environment => 'production';

    my $app = do "$RealBin/../bin/app.pl";
    my $server = Plack::Handler::FCGI->new(nproc => 5, detach => 1);

    $server->run($app);

Make sure you chmod +x dispatch.fcgi.
Here is an example lighttpd config.

    fastcgi.server += (
        "/atommq" => ((
            "socket" => "/tmp/fcgi.sock",
            "check-local" => "disable",
            "bin-path" => "/path/to/AtomMQ/public/dispatch.fcgi",
        )),
    )

Now AtomMQ will be running via FastCGI under /atommq.

=head1 PSGI

AtomMQ can be run in a L<PSGI> environment via L<Plack>.
You will need to have L<Plack> installed.
To deploy AtomMQ, just run:

    plackup -p 5000 /path/to/AtomMQ/bin/app.pl

Now AtomMQ is running on port 5000 via the L<HTTP::Server::PSGI> web server.
Of course you can use any PSGI/Plack web server via the -s option to plackup.

=head1 MOTIVATION

I like messaging systems because they make it so easy to create scalable
applications.
Existing message brokers are great for creating message queues.
But once a consumer reads a message off of a queue, it is gone.
I needed a system to publish events such that multiple heterogeneous services
could subscribe to them.
So I really needed a message bus, not a message queue.
I could for example have used something called topics in ActiveMQ,
but I have found them to have issues with persistence.
Actually, I have found ActiveMQ to be broken in general.
An instance I manage has to be restarted every day.
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
