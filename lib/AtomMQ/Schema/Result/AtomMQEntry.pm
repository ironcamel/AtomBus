package AtomMQ::Schema::Result::AtomMQEntry;
use strict;
use warnings;
use base 'DBIx::Class::Core';

__PACKAGE__->table("atommq_entry");

__PACKAGE__->add_columns(
  order_id     => { data_type => "integer", is_nullable => 0,
                    is_auto_increment => 1 },
  id           => { data_type => "varchar", is_nullable => 0, size => 100 },
  feed_title   => { data_type => "varchar", is_nullable => 0, size => 255,
                    is_foreign_key => 1 },
  title        => { data_type => "text",    is_nullable => 0 },
  author_name  => { data_type => "varchar", is_nullable => 1, size => 255 },
  author_email => { data_type => "varchar", is_nullable => 1, size => 255 },
  updated      => { data_type => "varchar", is_nullable => 0, size => 100 },
  content      => { data_type => "text",    is_nullable => 0 },
);
__PACKAGE__->set_primary_key("order_id");
__PACKAGE__->add_unique_constraint("id_unique", ["id"]);

__PACKAGE__->belongs_to(
  "feed_title",
  "AtomMQ::Schema::Result::AtomMQFeed",
  { title => "feed_title" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "CASCADE" },
);

=head1 NAME

AtomMQ::Schema::Result::AtomMQEntry

=head1 ACCESSORS

=head2 order_id

  data_type: 'integer'
  is_nullable: 0
  is_auto_increment: 1

=head2 id

  data_type: 'varchar'
  is_nullable: 0
  size: 100

=head2 feed_title

  data_type: 'varchar'
  is_foreign_key: 1
  is_nullable: 0
  size: 255

=head2 title

  data_type: 'text'
  is_nullable: 0

=head2 author_name

  data_type: 'varchar'
  is_nullable: 1
  size: 255

=head2 author_email

  data_type: 'varchar'
  is_nullable: 1
  size: 255

=head2 updated

  data_type: 'varchar'
  is_nullable: 0
  size: 100

=head2 content

  data_type: 'text'
  is_nullable: 0

=head1 RELATIONS

=head2 feed_title

Type: belongs_to

Related object: L<AtomMQ::Schema::Result::AtomMQFeed>

=cut

1;
