package RateLimiter;
use strict;
use warnings;
use Time::HiRes qw(time);

sub new {
    my ($class, $rate_per_second, $capacity) = @_;
    die "Rate must be positive" if $rate_per_second <= 0;
    die "Capacity must be positive" if $capacity <= 0;
    
    my $self = {
        rate => $rate_per_second,
        capacity => $capacity,
        tokens => $capacity,
        last_refill => time,
    };
    
    bless $self, $class;
    return $self;
}

sub _refill {
    my ($self) = @_;
    
    my $now = time;
    my $time_passed = $now - $self->{last_refill};
    
    if ($time_passed > 0) {
        my $tokens_to_add = $time_passed * $self->{rate};
        $self->{tokens} += $tokens_to_add;
        
        if ($self->{tokens} > $self->{capacity}) {
            $self->{tokens} = $self->{capacity};
        }
        
        $self->{last_refill} = $now;
    }
}

sub allow_request {
    my ($self) = @_;
    
    $self->_refill();
    
    if ($self->{tokens} >= 1) {
        $self->{tokens}--;
        return 1;
    }
    
    return 0;
}

sub allow_requests {
    my ($self, $count) = @_;
    
    $self->_refill();
    
    if ($self->{tokens} >= $count) {
        $self->{tokens} -= $count;
        return 1;
    }
    
    return 0;
}

sub get_available_tokens {
    my ($self) = @_;
    $self->_refill();
    return int($self->{tokens});
}

sub get_wait_time {
    my ($self) = @_;
    $self->_refill();
    
    if ($self->{tokens} >= 1) {
        return 0;
    }
    
    return (1 - $self->{tokens}) / $self->{rate};
}

sub reset {
    my ($self) = @_;
    $self->{tokens} = $self->{capacity};
    $self->{last_refill} = time;
}

package main;

my $limiter = RateLimiter->new(5, 10);

print "Available tokens: " . $limiter->get_available_tokens() . "\n";

for my $i (1..12) {
    if ($limiter->allow_request()) {
        print "Request $i: Allowed\n";
    } else {
        my $wait = $limiter->get_wait_time();
        print "Request $i: Rate limited. Wait $wait seconds\n";
    }
}

print "Available tokens: " . $limiter->get_available_tokens() . "\n";

sleep(2);

print "After 2 seconds sleep\n";
print "Available tokens: " . $limiter->get_available_tokens() . "\n";

if ($limiter->allow_requests(3)) {
    print "Bulk request for 3 tokens: Allowed\n";
}

$limiter->reset();
print "After reset - Available tokens: " . $limiter->get_available_tokens() . "\n";

1;
