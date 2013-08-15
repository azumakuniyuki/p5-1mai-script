#!/usr/bin/env perl
=head1 DESCRIPTION
    Template for a single file script with perl

=head1 USAGE
    Try --help option
=cut

#   ____ _     ___ 
#  / ___| |   |_ _|
# | |   | |    | | 
# | |___| |___ | | 
#  \____|_____|___|
#                  
package CLI;
use strict;
use warnings;
use IO::File;
use Fcntl qw(:flock);
use File::Basename qw/basename/;
use Sys::Syslog;
use Time::Piece;
use Data::Dumper;

sub new {

    my $class = shift;
    my $argvs = { @_ };
    my $param = {};
    my $thing = undef;

    return $class if ref $class eq __PACKAGE__;
    $param = {
        'started' => Time::Piece->new,
        'pidfile' => $argvs->{'pidfile'} || q(),
        'verbose' => $argvs->{'verbose'} || 0,
        'command' => $argvs->{'command'} ? $argvs->{'command'} : $0,
        'runmode' => $argvs->{'runmode'} || 1,
        'syslog' => $argvs->{'syslog'} || { 'enabled' => 0, 'facility' => 'user' },
        'stream' => {
            'stdin'  => -t STDIN  ? 1 : 0,
            'stdout' => -t STDOUT ? 1 : 0,
            'stderr' => -t STDERR ? 1 : 0,
        },
    };
    $thing = bless $param, __PACKAGE__;
    $thing->mkpf;
    return $thing;
}

sub stdin { shift->{'stream'}->{'stdin'} }
sub stdout { shift->{'stream'}->{'stdout'} }
sub stderr { shift->{'stream'}->{'stderr'} }
sub r { my( $x, $y ) = @_; $x->{'runmode'} = $y if defined $y; return $x->{'runmode'}; }
sub v { my( $x, $y ) = @_; $x->{'verbose'} = $y if defined $y; return $x->{'verbose'}; }

sub l {
    # @Description  Interface to UNIX syslog(3)
    # @Param <str>  (String) Log message
    # @Param <str>  (String) Syslog level
    # @Return       (Integer) 1 = No error occurred
    #               (Integer) 0 = No log message or Error occurred
    #
    my $self = shift; return 0 unless $self->{'syslog'}->{'enabled'};
    my $messages = shift || ''; return 0 unless length $messages;
    my $priority = shift || 'LOG_INFO';
    my $facility = $self->{'facility'} || 'LOG_USER';

    # Don't send message to syslogd if it's disabled in 'syslog' property
    return 0 unless $self->{'syslog'}->{'enabled'};
    return 0 unless length $messages;

    my $syslogps = { 
        'a' => 'LOG_ALERT', 'c' => 'LOG_CRIT', 'e' => 'LOG_ERR', 'w' => 'LOG_WARNING',
        'n' => 'LOG_NOTICE', 'i' => 'LOG_INFO', 'd' => 'LOG_DEBUG',
    };
    my $logargvs = [ 'ndelay', 'pid', 'nofatal' ];
    my $identity = basename $0;
    my $username = $ENV{'LOGNAME'} || $ENV{'USER'} || 'NOBODY';

    $priority = $syslogps->{ $priority } if length $priority == 1;
    $priority = 'LOG_INFO' unless grep { $priority eq $_ } values %$syslogps;

    $messages .= sprintf( " by uid=%d(%s)", $>, $username );
    $messages =~ y{\n\r}{}d;
    $messages =~ y{ }{}s;

    openlog( $identity, join( ',', @$logargvs ), $facility ) || return 0;
    syslog( $priority, $messages ) || return 0;
    closelog() || return 0;

    return 1;
}

sub e {
    # @Description  Print error message and exit
    # @Param <mesg> (String) Error message text
    # @Param <bool> (Boolean) continue or not
    # @Return       1 or exit(1)
    my $self = shift;
    my $mesg = shift; return 0 unless length $mesg;
    my $cont = shift || 0;

    $self->l( $mesg, 'e' ) if $self->{'syslog'}->{'enabled'};
    printf( STDERR " * error0: %s\n", $mesg ) if $self->stderr;
    printf( STDERR " * error0: ******** ABORT ********\n" ) if $self->stderr;
    $cont ? return 1 : exit(1);
}

sub p {
    # @Description  Print debug message
    # @Param <mesg> (String) Debug message text
    # @Param <level>(Integer) Debug level
    # @Return       0 or 1
    my $self = shift;
    my $mesg = shift; return 0 unless length $mesg;
    my $rung = shift || 1;

    return 0 unless $self->stderr;
    return 0 unless $self->v;
    return 0 unless $self->v >= $rung;

    chomp $mesg; printf( STDERR " * debug%d: %s\n", $rung, $mesg );
    return 1;

}

sub mkpf {
    # @Description  Create process id file
    # @Return       0 or 1
    my $self = shift;
    my $file = undef;
    my $text = '';

    return 0 unless $self->{'pidfile'};
    return 0 if -e  $self->{'pidfile'};

    $file = IO::File->new( $self->{'pidfile'}, 'w' ) || return 0;
    $text = sprintf( "%d\n%s\n", $$, $self->{'command'} );

    flock( $file, LOCK_EX ) ? $file->print( $text ) : return 0;
    flock( $file, LOCK_UN ) ? $file->close : return 0;
    return 1;
}

sub rmpf { 
    # @Description  Remove process id file
    # @Return       1
    my $self = shift; 
    return 0 unless -f $self->{'pidfile'};
    unlink $self->{'pidfile'};
    return 1;
}
sub DESTROY { shift->rmpf }
1;

#                  _       
#  _ __ ___   __ _(_)_ __  
# | '_ ` _ \ / _` | | '_ \ 
# | | | | | | (_| | | | | |
# |_| |_| |_|\__,_|_|_| |_|
#                          
package main;
use strict;
use warnings;

BEGIN {

    if( @ARGV ) {

        if( $ARGV[0] eq '--modules' ) {

            require IO::File;
            my $filehandle = IO::File->new( $0, 'r' ) || die $!;
            my $modulelist = [];
            my $modulename = '';

            while( ! $filehandle->eof ) {

                my $r = $filehandle->getline;
                next if $r =~ /\A\s*#/;
                next if $r =~ /\A=/;
                next if $r =~ /\A\s*\z/;
                next if $r =~ /\buse (?:strict|warnings|utf8)/;

                $modulename = $1 if $r =~ m{\b(?:use|require)[ ]+([A-Za-z][0-9A-Za-z:]+)[ ;]};

                next unless $modulename;
                next if grep { $modulename eq $_ } @$modulelist;
                push @$modulelist, $modulename; $modulename = q();
            }
            $filehandle->close;
            printf( "%s\n", $_ ) for @$modulelist;
            exit 0;

        } elsif( $ARGV[0] eq '--cpanm' ) {

            my $commandurl = 'http://xrl.us/cpanm';
            my $searchpath = [ '/usr/local/bin/', '/usr/bin/', '/bin/', './' ];
            my $commandset = { 'wget' => '-c', 'curl' => '-LOk' };
            my $scriptpath = qx/which cpanm/; chomp $scriptpath;
            my $getcommand = q();

            if( -x $scriptpath ) {
                printf "%s\n", $scriptpath;
                exit 0;
            }

            foreach my $e ( keys %$commandset ) {

                $getcommand = qx/which $e/; chomp $getcommand;
                $getcommand = q() unless -x $getcommand;
                $getcommand ||= shift [ grep { $_ .= $e; $_ if -x $_ } @$searchpath ];
                next unless $getcommand;

                $getcommand .= ' '.$commandset->{ $e };
                last;
            }

            $scriptpath = './cpanm';
            if( -f $scriptpath ) {
                chmod( '0755', $scriptpath );
                printf( "%s\n", $scriptpath ); 
                exit 0;
            }
            system qq($getcommand $commandurl > /dev/null 2>&1);
            chmod( '0755', $scriptpath ) if -x $scriptpath;
            printf "%s\n", $scriptpath;
            exit 0;
        }
    }
}

use Getopt::Long qw/:config posix_default no_ignore_case bundling auto_help/;
use File::Basename qw/basename/;
use Data::Dumper;

my $Version = '0.0.1';
my $Setting = {};
my $Default = {
    'syslog' => { 'enabled' => 0, 'facility' => 'user' },
};
my $Options = {
    'exec' => ( 1 << 0 ),
    'test' => ( 1 << 1 ),
    'neko' => ( 1 << 2 ),
};
my $Command = CLI->new( 
    'command' => join( ' ', $0, @ARGV ),
    'pidfile' => sprintf( "/tmp/%s.pid", basename $0 ),
);
$Command->r( parseoptions() );

if( $Command->r & $Options->{'exec'} ) {

}

sub parseoptions {

    my $r = 0;      # Run mode value
    my $p = {};     # Parsed options
    my $c = q();    # Configuration file

    Getopt::Long::GetOptions( $p, 'conf|C=s', 'verbose|v+',
        'data'     => sub { print <DATA>; exit 0; },
        'help'      => sub { help(); exit 0; },
        'version'   => sub { printf( STDERR "%s\n", $Version ); exit 0; },
    );

    if( $p->{'conf'} ) {
        # Load configuration file specified with -C or --conf option
        $c = $p->{'conf'};

    } else {
        # Try to load scriptname.cf as a confguration file
        $c = __FILE__; $c =~ s/[.]pl//; $c .= '.cf';
    }

    eval { $Setting = do $c } if -f $c;
    $Command->e( $@ ) if $@;
    $Command->e( 'Empty configuration: '.$c ) unless $Setting;
    $Command->e( 'Invalid format: '.$c ) unless ref $Setting eq q|HASH|;

    $Setting = $Default unless keys %$Setting;
    $Command->{'syslog'} = $Setting->{'syslog'} || $Default->{'syslog'};

    $r |= $Options->{'exec'};

    $Command->v( $p->{'verbose'} );
    $Command->p( sprintf( "Configuration file = %s", $c ), 1 ) if -f $c;
    $Command->p( sprintf( "Debug level = %d", $Command->v ), 1 );
    $Command->p( sprintf( "Run mode = %d", $r ), 1 );

    if( $Command->{'syslog'}->{'enabled'} ) {
        $Command->p( sprintf( "Syslog enabled = %d", $Command->{'syslog'}->{'enabled'} ), 2 );
        $Command->p( sprintf( "Syslog Facility = %s", $Command->{'syslog'}->{'facility'} ), 2 );
    }
    return $r;
}

sub help {
    printf( STDERR "%s OPTIONS \n", $0 );
    printf( STDERR "  -C, --conf <file>   : Specify a configuration file\n" );
    printf( STDERR "\n" );
    printf( STDERR '  --help              : Help screen'."\n" );
    printf( STDERR '  --version           : Print the version number'."\n" );
    printf( STDERR '  -v, --verbose       : Verbose mode'."\n" );
    printf( STDERR '  --cpanm             : Find or download cpanm command'."\n" );
    printf( STDERR '  --modules           : Print required perl module list'."\n" );
    printf( STDERR "\n" );
}

__DATA__
