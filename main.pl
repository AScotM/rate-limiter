package RateLimiter;
use strict;
use warnings;
use Time::HiRes qw(time sleep);
use Scalar::Util qw(looks_like_number blessed);

sub new {
    my ($class, $rate_per_second, $capacity) = @_;

    _validate_constructor_args($rate_per_second, $capacity);

    my $now = time();

    my $self = {
        rate         => 0 + $rate_per_second,
        capacity     => 0 + $capacity,
        tokens       => 0 + $capacity,
        last_refill  => $now,
        total_checks => 0,
        total_denied => 0,
        total_grants => 0,
        created_at   => $now,
    };

    bless $self, $class;
    return $self;
}

sub _validate_constructor_args {
    my ($rate_per_second, $capacity) = @_;

    die "Rate must be defined\n" unless defined $rate_per_second;
    die "Capacity must be defined\n" unless defined $capacity;
    die "Rate must be numeric\n" unless looks_like_number($rate_per_second);
    die "Capacity must be numeric\n" unless looks_like_number($capacity);

    $rate_per_second += 0;
    $capacity += 0;

    die "Rate must be positive\n" unless $rate_per_second > 0;
    die "Capacity must be positive\n" unless $capacity > 0;
}

sub _validate_count {
    my ($count) = @_;

    die "Count must be defined\n" unless defined $count;
    die "Count must be numeric\n" unless looks_like_number($count);

    $count += 0;

    die "Count must be positive\n" unless $count > 0;

    return $count;
}

sub _validate_object {
    my ($self) = @_;

    die "RateLimiter object is required\n" unless defined $self;
    die "Invalid RateLimiter object\n" unless ref($self) && blessed($self) && $self->isa(__PACKAGE__);

    for my $required_key (qw(rate capacity tokens last_refill total_checks total_denied total_grants created_at)) {
        die "Corrupted limiter state: missing '$required_key'\n" unless exists $self->{$required_key};
    }

    die "Corrupted limiter state: rate must be numeric\n" unless looks_like_number($self->{rate});
    die "Corrupted limiter state: capacity must be numeric\n" unless looks_like_number($self->{capacity});
    die "Corrupted limiter state: tokens must be numeric\n" unless looks_like_number($self->{tokens});
    die "Corrupted limiter state: last_refill must be numeric\n" unless looks_like_number($self->{last_refill});

    die "Corrupted limiter state: rate must be positive\n" unless $self->{rate} > 0;
    die "Corrupted limiter state: capacity must be positive\n" unless $self->{capacity} > 0;
}

sub _clamp_tokens {
    my ($self) = @_;

    if ($self->{tokens} < 0) {
        $self->{tokens} = 0;
    }

    if ($self->{tokens} > $self->{capacity}) {
        $self->{tokens} = $self->{capacity};
    }
}

sub _refill {
    my ($self) = @_;

    $self->_validate_object();

    my $now = time();

    if ($now < $self->{last_refill}) {
        $self->{last_refill} = $now;
        return;
    }

    my $time_passed = $now - $self->{last_refill};

    if ($time_passed <= 0) {
        return;
    }

    my $tokens_to_add = $time_passed * $self->{rate};
    $self->{tokens} += $tokens_to_add;
    $self->{last_refill} = $now;

    $self->_clamp_tokens();
}

sub consume {
    my ($self, $count) = @_;

    $self->_validate_object();
    $count = _validate_count($count);

    $self->_refill();
    $self->{total_checks}++;

    if ($self->{tokens} >= $count) {
        $self->{tokens} -= $count;
        $self->_clamp_tokens();
        $self->{total_grants}++;
        return 1;
    }

    $self->{total_denied}++;
    return 0;
}

sub allow_request {
    my ($self) = @_;
    return $self->consume(1);
}

sub allow_requests {
    my ($self, $count) = @_;
    return $self->consume($count);
}

sub wait_for_tokens {
    my ($self, $count, $max_wait_seconds) = @_;

    $self->_validate_object();
    $count = _validate_count($count);

    if (defined $max_wait_seconds) {
        die "Max wait time must be numeric\n" unless looks_like_number($max_wait_seconds);
        $max_wait_seconds += 0;
        die "Max wait time cannot be negative\n" if $max_wait_seconds < 0;
    }

    my $start = time();

    while (1) {
        return 1 if $self->consume($count);

        my $wait_time = $self->get_wait_time($count);
        $wait_time = 0 if $wait_time < 0;
        $wait_time = 0.001 if $wait_time == 0;

        if (defined $max_wait_seconds) {
            my $elapsed = time() - $start;
            return 0 if $elapsed >= $max_wait_seconds;

            my $remaining = $max_wait_seconds - $elapsed;
            $wait_time = $remaining if $wait_time > $remaining;
            return 0 if $wait_time <= 0;
        }

        sleep($wait_time);
    }
}

sub get_available_tokens {
    my ($self) = @_;
    $self->_validate_object();
    $self->_refill();
    return int($self->{tokens});
}

sub get_available_tokens_raw {
    my ($self) = @_;
    $self->_validate_object();
    $self->_refill();
    return $self->{tokens};
}

sub get_capacity {
    my ($self) = @_;
    $self->_validate_object();
    return $self->{capacity};
}

sub get_rate {
    my ($self) = @_;
    $self->_validate_object();
    return $self->{rate};
}

sub get_wait_time {
    my ($self, $count) = @_;

    $self->_validate_object();
    $count = 1 unless defined $count;
    $count = _validate_count($count);

    $self->_refill();

    if ($self->{tokens} >= $count) {
        return 0;
    }

    return ($count - $self->{tokens}) / $self->{rate};
}

sub get_statistics {
    my ($self) = @_;

    $self->_validate_object();

    return {
        rate         => $self->{rate},
        capacity     => $self->{capacity},
        tokens       => $self->{tokens},
        total_checks => $self->{total_checks},
        total_grants => $self->{total_grants},
        total_denied => $self->{total_denied},
        created_at   => $self->{created_at},
        uptime       => time() - $self->{created_at},
    };
}

sub reset {
    my ($self) = @_;
    $self->_validate_object();

    $self->{tokens}       = $self->{capacity};
    $self->{last_refill}  = time();
    $self->{total_checks} = 0;
    $self->{total_denied} = 0;
    $self->{total_grants} = 0;
}

1;

package main;
use strict;
use warnings;

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

print "Available tokens after loop: " . $limiter->get_available_tokens() . "\n";

sleep(2);

print "After 2 seconds sleep\n";
print "Available tokens: " . $limiter->get_available_tokens() . "\n";

if ($limiter->allow_requests(3)) {
    print "Bulk request for 3 tokens: Allowed\n";
} else {
    my $wait = $limiter->get_wait_time(3);
    print "Bulk request for 3 tokens: Rate limited. Wait $wait seconds\n";
}

my $stats = $limiter->get_statistics();
print "Total checks: $stats->{total_checks}\n";
print "Total grants: $stats->{total_grants}\n";
print "Total denied: $stats->{total_denied}\n";

$limiter->reset();
print "After reset - Available tokens: " . $limiter->get_available_tokens() . "\n";
