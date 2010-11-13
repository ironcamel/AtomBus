package AtomMQ::Schema::Result::AtomMQEntry;
use strict;
use warnings;
use base 'DBIx::Class::Core';

__PACKAGE__->table("atommq_entry");

__PACKAGE__->add_columns(
    id => {
        data_type => 'integer',
        is_nullable => 0,
        is_auto_increment => 1,
    },
    feed => {
        data_type => 'varchar',
        is_nullable => 0,
        size => 255,
    },
    title => {
        data_type => 'varchar',
        is_nullable => 0,
        size => 255,
    },
    content => {
        data_type => 'text',
        is_nullable => 0,
    },
);

__PACKAGE__->set_primary_key("id");

1;
