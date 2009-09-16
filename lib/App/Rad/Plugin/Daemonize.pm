package App::Rad::Plugin::Daemonize;
use POSIX      ();
use File::Temp ();
use Carp       ();

sub daemonize {
   my $c    = shift;
   my $func = shift;
   my %pars = @_;
   $c->register("Win32_Daemon", sub {
                                     $c->write_pidfile($pars{pid_file});
                                     $c->change_procname($pars{proc_name}) if $c->check_root;
                                     $c->chroot($pars{chroot_dir}) if $c->check_root;
                                     $c->change_user($pars{user}) if exists $pars{user};
                                     $c->signal_handlers($pars{signal_handlers});
                                     $func->($c);
                                    }) if $^O eq "MSWin32";
   $c->register("stop"   , sub{
                              my $c = shift;
                              Carp::croak "You are not root" 
                                 if ($pars{check_root} and exists $pars{check_root})
                                    and not $c->check_root;
                              Carp::croak "Daemon $0 is not running" unless $c->is_running;
                              "Stopping $0: " . ($c->stop ? "OK" : "NOK")
                           });
   $c->register("restart", sub{
                              my $c = shift;
                              Carp::croak "You are not root" 
                                 if ($pars{check_root} and exists $pars{check_root})
                                    and not $c->check_root;
                              $c->execute("stop") && $c->execute("start");
                           });
   $c->register("status" , sub{
                              my $c = shift;
                              Carp::croak "You are not root" 
                                 if ($pars{check_root} and exists $pars{check_root})
                                    and not $c->check_root;
                              $c->is_running ? "$0 Daemon is running" : "$0 Daemon is not running"
                           });
   $c->register("start"  , sub{
                              my $c = shift;
                              if(exists $pars{dont_use_options} and not $pars{dont_use_options}) {
                                 my %options = %{ $c->options };
                                 for my $opt (keys %options) {
                                    next if exists $pars{$opt};
                                    $pars{$opt} = $options{$opt};
                                 }
                              }
                              Carp::croak "You are not root" 
                                 if ($pars{check_root} and exists $pars{check_root})
                                    and not $c->check_root;
                              Carp::croak "Daemon $0 is already running" if $c->is_running;
                              my $daemon_pid = $c->detach unless $pars{no_detach};
                              print "Starting $0 (pid: $daemon_pid): OK$/";
                              if($^O ne "MSWin36") {
                                 $c->write_pidfile($pars{pid_file});
                                 $c->change_procname($pars{proc_name}) if $c->check_root;
                                 $c->chroot($pars{chroot_dir}) if $c->check_root;
                                 $c->change_user($pars{user}) if exists $pars{user};
                                 $c->signal_handlers($pars{signal_handlers});
                                 $func->($c);
                              }
                           });
}

sub detach {
   my $c = shift;

   if($^O ne "MSWin32"){
      umask(0);
      $SIG{'HUP'} = 'IGNORE';
      my $child = fork();

      if($child < 0) {
          Carp::croak "Fork failed ($!)";
      }

      if( $child ) {
          exit 0;
      }

      close(STDIN);
      POSIX::setsid || Carp::croak "Can't start a new session: $!";
      return $$
   } else {
      require Win32::Process;
      my $proc;
      Win32::Process::Create(
                             $proc,
                             qq{$^X},
                             "perl $0 Win32_Daemon "
                                . (
                                   join " ", @ARGV
                                  ),
                             0,
                             Win32::Process->DETACHED_PROCESS,
                             ".",
                            );
      return $proc->GetProcessID
   }
}

sub chroot {
   my $c   = shift;
   my $dir = shift;

   $dir = File::Temp::tmpnam unless defined $dir;
   mkdir $dir and $c->stash->{chroot_dir} = $dir;

   chroot $dir;
}

sub change_user {
   my $c    = shift;
   my $user = shift;
   my $uid;

   if($user =~ /^\d+$/){
      $uid = $user;
   } else {
      $uid = getpwnam($user);
   }
   defined $uid or die "User \"$user\" do not exists";
   POSIX::setuid($uid);
}

sub check_root {
   my $c = shift;
   $< == 0;
}

sub write_pidfile {
   my $c    = shift;
   my $file = shift;

   if(not defined $file and not exists $c->stash->{pidfile}) {
      ($file = $0) =~ s{^.*/}{};
      $file =~ s/\./_/g;
      $file = ".$file.pid";
      $file = $c->path . "/$file";
   } elsif (not defined $file) {
      $file = $c->stash->{pidfile};
   }
   $c->stash->{pidfile} = $file;
   open my $PIDFILE, ">", $file;
   my $ret = print {$PIDFILE} $$, $/;
   close $PIDFILE;
   return unless -f $file;
   $ret
}

sub change_procname {
   my $c    = shift;
   my $name = shift;
   ($name = $0) =~ s{^.*/}{};
   $0 = $name;
}

sub read_pidfile {
   my $c    = shift;
   my $file = shift;

   if(not defined $file and not exists $c->stash->{pidfile}) {
      ($file = $0) =~ s{^.*/}{};
      $file =~ s/\./_/g;
      $file = ".$file.pid";
      $file = $c->path . "/$file";
   } elsif (not defined $file) {
      $file = $c->stash->{pidfile};
   }
   $c->stash->{pidfile} = $file;
   return unless -f $file;
   open my $PIDFILE, "<", $file;
   my $ret = scalar <$PIDFILE>;
   close $PIDFILE;
   $ret
}

sub stop {
   my $c    = shift;
   my $file = shift;

   $c->kill(15, $file);
}

sub kill {
   my $c      = shift;
   my $signal = shift;
   my $file   = shift;

   my $pid = $c->read_pidfile($file);
   return unless defined $pid and $pid;
   kill $signal => $pid;
}

sub is_running {
   my $c    = shift;
   my $file = shift;

   $c->kill(0, $file);
}

sub signal_handlers {
   my $c = shift;
   my $funcs;
   my $count;
   if(ref $_[0] eq "HASH") {
      $funcs = shift;
   } else {
      $funcs = { @_ };
   }

   for my $sig (keys %$funcs) {
      my $func = $funcs->{ $sig };
      $SIG{ $sig } = sub{$func->($c)} and $count++;
   }
   $count
}

42
