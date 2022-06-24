use highlighter:ver<0.0.5>:auth<zef:lizmat>;
use paths:ver<10.0.4>:auth<zef:lizmat>;
use Files::Containing:ver<0.0.5>:auth<zef:lizmat>;

my constant BON  = "\e[1m";
my constant BOFF = "\e[22m";

# Make sure we remember if there's a human watching (terminal connected)
my $isa-tty := $*OUT.t;

my constant @raku-extensions = <
   raku rakumod rakutest nqp t pm6 pl6
>;

# sane way of quitting
my sub meh($message) { exit note $message }

# quit if unexpected named arguments
my sub meh-if-unexpected(%_) {
    meh "Unexpected parameters: %_.keys()";

# is a needle a simple Callable?
my sub is-simple-Callable($needle) {
    Callable.ACCEPTS($needle) && !Regex.ACCEPTS($needle)
}

# process all alternate names / values into a single value
my sub named-arg(%args, *@names) {
    return %args.DELETE-KEY($_) if %args.EXISTS-KEY($_) for @names;
    Nil
}

# process all alternate names / values into a Map
my sub named-args(%args, *%wanted) {
    Map.new: %wanted.kv.map: -> $name, $keys {
        if $keys =:= True {
            Pair.new($name, %args.DELETE-KEY($name)) if %args.EXISTS-KEY($name)
        }
        else {
            Pair.new($name, %args.DELETE-KEY($_))
              with $keys.first: { %args.EXISTS-KEY($_) }
        }
    }
}

# add any lines before / after in a result
my sub add-before-after($io, @initially-selected, int $before, int $after) {
    my str @lines = $io.lines;
    @lines.unshift: "";   # make 1-base indexing natural
    my int $last-linenr = @lines.end;

    my int8 @seen;
    my @selected;
    for @initially-selected {
        my int $linenr = .key;
        if $before {
            for max($linenr - $before, 1) ..^ $linenr -> int $_ {
                @selected.push: Pair.new($_, @lines.AT-POS($_))
                  unless @seen.AT-POS($_)++;
            }
        }

        @selected.push: $_ unless @seen.AT-POS($linenr)++;

        if $after {
            for $linenr ^.. min($linenr + $after, $last-linenr ) -> int $_ {
                @selected.push: Pair.new($_,@lines.AT-POS($_))
                  unless @seen.AT-POS($_)++;
            }
        }
    }

    @selected
}

my sub MAIN($needle is copy, $dir = ".", *%_) is export {
    $needle .= trim;
    if $needle.starts-with('/') && $needle.ends-with('/')
      || $needle.indices('*') == 1 {
        $needle .= EVAL;
    }
    elsif $needle.starts-with('{') && $needle.ends-with('}') {
        $needle = ('-> $_ ' ~ $needle).EVAL;
    }

    temp $*OUT;
    $*OUT = open($_, :w) with named-arg %_, <output-file>;

    my $file;
    my $dir;

    named-arg(%_, <l files-only files-with-matches>)
      ?? files-only($needle, $dir, $file, $dir, %_)
      !! want-lines($needle, $dir, $file, $dir, %_)
}

my sub files-only($needle, $root, $file, $dir, %_ --> Nil) {
    my $additional := named-args %_,
      ignorecase   => <i ignorecase ignore-case>,
      ignoremark   => <m ignoremark ignore-mark>,
      invert-match => <v invert-match>,
      :batch, :degree,
    ;
    meh-if-unexpected(%_);

    .say for files-containing
       $needle, $root, :$file, :$dir, :files-only, :offset(1), |$additional,
    ;
}

my sub want-lines($needle, $root, $file, $dir, %_ --> Nil) {
    my $seq := files-containing
      $needle, $root, :$file, :$dir, :offset(1), |named-args
        ignorecase   => <i ignorecase ignore-case>,
        ignoremark   => <m ignoremark ignore-mark>,
        invert-match => <v invert-match>,
        :max-count, :batch, :degree,
    ;

    my UInt() $before = $_ with named-arg %_, <B before-context>;
    my UInt() $after  = $_ with named-arg %_, <A after-context>;
    $before = $after  = $_ with named-arg %_, <C context>;

    my Bool() $line-number;
    my Bool() $highlight;
    my Bool() $no-filename;
    my Bool() $only-matching;

    if %_<human> // $isa-tty {
        $line-number = $highlight     = True;
        $no-filename = $only-matching = False;
    }

    $line-number   = $_ with named-arg %_, <n line-number>
    $highlight     = $_ with named-arg %_, <highlight>;
    $no-filename   = $_ with named-arg %_, <h no-filename>
    $only-matching = $_ with named-arg %_, <o only-matching>;

    ($before || $after)  && !$only-matching;
      ?? lines-with-context($seq, $needle, $before, $after, %_)
      !! just-lines($seq, $needle, %_);
}

my sub lines-with-context($seq, $needle, $before, $after, %_) {
    my int $nr-files;

    for $seq {
        say "" if $nr-files++;

        my $io := .key;
        say $io.relative;

        my @selected := add-before-after($io, .value, $before, $after);
        my $format   := '%' ~ (@selected.tail.key.chars + 1) ~ 'd:';

        say sprintf($format, .key) ~ highlighter .value, $needle, BON, BOFF
          for @selected;
    }
}

    if $human {
        if $before || $after {
        }
        else {
            for $seq {
                say .key.relative;
                my @selected = $seq;
                my $width := .value.tail.key.chars + 1;
                for .value {
                    say sprintf('%' ~ $width ~ 'd', .key)
                      ~ ': '
                      ~ highlighter .value.trim, $needle, BON, BOFF
                }
                say "";
            }
        }
    }
    else {
        if $before || $after {
            for $seq {
                my $io   := .key;
                my $file := $io.relative;
                my @selected := add-before-after($io, .value, $before, $after);
                my int $last-linenr = @selected[0].key - 1;

                for @selected {
                    my int $linenr = .key;
                    say "--" if $last-linenr != $linenr - 1;
                    say "$file: " ~ .value;
                    $last-linenr = $linenr;
                }
                say "--";
            }
        }
        else {
            for $seq {
                my $file := .key.relative;
                say "$file: " ~ .value.trim for .value;
            }
        }
    }
}

=begin pod

=head1 NAME

App::Rak - a CLI for searching strings in files

=head1 SYNOPSIS

=begin code :lang<bash>

$ rak foo      # look for "foo" in current directory recursively

$ rak foo bar  # look for "foo" in directory "bar" recursively

$ rak '/ << foo >> /'    # look for "foo" as word in current directory

$ raku foo --files-only  # look for "foo", only produce filenames

$ raku foo --before=2 --after=2  # also produce 2 lines before and after

=end code

=head1 DESCRIPTION

App::Rak provides a CLI called C<rak> that allows you to look for a needle
in (a selection of files) from a given directory recursively.

Note: this is still very much in alpha development phase.  Comments and
suggestions are more than welcome!

=head1 AUTHOR

Elizabeth Mattijsen <liz@raku.rocks>

Source can be located at: https://github.com/lizmat/App-Rak .
Comments and Pull Requests are welcome.

If you like this module, or what I’m doing more generally, committing to a
L<small sponsorship|https://github.com/sponsors/lizmat/>  would mean a great
deal to me!

=head1 COPYRIGHT AND LICENSE

Copyright 2022 Elizabeth Mattijsen

This library is free software; you can redistribute it and/or modify it under the Artistic License 2.0.

=end pod

# vim: expandtab shiftwidth=4
