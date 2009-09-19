use Test::More tests => 6;
use File::Temp qw/:POSIX/;

use App::Rad qw/Daemonize/;
use App::Rad::Tester;

my $c = get_controller;

ok($c->write_pidfile(my $filename = tmpname));
open my $FILE, "<", $filename || die "couldn't open file $filename";
my $pid_on_file = <$FILE>;
close $FILE;
if($pid_on_file =~ /^(\d+)$/){
   is($1, $$);
}
is($c->read_pidfile, $$ . $/);
ok($c->write_pidfile(my $filename = tmpname));
open my $FILE, "<", $filename || die "couldn't open file $filename";
my $pid_on_file = <$FILE>;
close $FILE;
if($pid_on_file =~ /^(\d+)$/){
   is($1, $$);
}
chomp(my $ret = $c->read_pidfile);
is($c->read_pidfile, $$ . $/);
