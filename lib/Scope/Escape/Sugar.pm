=head1 NAME

Scope::Escape::Sugar - whizzy syntax for non-local control transfer

=head1 SYNOPSIS

	use Scope::Escape::Sugar
		qw(with_escape_function with_escape_continuation);

	{ with_escape_function $e; ...; $e->($r); ...; }
	with_escape_function $e { ...; $e->($r); ...; }
	$res = with_escape_function($e { ...; $e->($r); ...; });

	{ with_escape_continuation $e; ...; $e->($r); ...; }
	with_escape_continuation $e { ...; $e->($r); ...; }
	$res = with_escape_continuation($e { ...; $e->($r); ...; });

	use Scope::Escape::Sugar qw(block return_from);

	{ block foo; ...; return_from foo $r; ...; }
	block foo { ...; return_from foo $r; ...; }
	$res = block(foo { ...; return_from foo $r; ...; });

	use Scope::Escape::Sugar qw(catch throw);

	{ catch "foo"; ...; }
	catch "foo" { ...; }
	$res = catch("foo" { ...; });
	throw("foo", $r);

=head1 DESCRIPTION

This module provides specialised syntax for non-local control transfer
(jumping between stack frames), mainly based on the operators in Common
Lisp.  The non-local control transfers behave exactly like those of
L<Scope::Escape>, which should be consulted for the semantic details.
This module provides more structured facilities, which take a variety
of approaches to referencing the stack frame to be transferred to.

All the keywords and functions exported by this module are lexically
scoped in the importing code.  That is, they are available from the
point of importation up to the end of the enclosing block.  This is
in contrast to the more common arrangement where exports are tied to a
package without regard for lexical boundaries.

=cut

package Scope::Escape::Sugar;

{ use 5.011002; }
use warnings;
use strict;

use B::Hooks::EndOfScope 0.05 ();
use Lexical::Sub 0.003 ();
use Scope::Escape 0.001 ();

our $VERSION = "0.000";

require XSLoader;
XSLoader::load(__PACKAGE__, $VERSION);

my %exportable = (
	with_escape_function => "keyword",
	with_escape_continuation => "keyword",
	block => "keyword",
	return_from => "keyword",
	catch => "keyword",
	throw => \&_throw,
);

sub import {
	my $package = shift;
	foreach(@_) {
		my $exp = $exportable{$_};
		if(!defined($exp)) {
			die "\"$_\" is not exported by the $package module\n"
				unless defined $exp;
		} elsif(ref($exp) eq "CODE") {
			Lexical::Sub->import($_ => $exp);
		} else {
			$^H{"Scope::Escape::Sugar/$_"} = 1;
		}
	}
}

=head1 KEYWORDS AND FUNCTIONS

The items shown here are mostly not ordinary functions.  Most are keywords
that introduce a form that has some special syntax, not conforming
to the ordinary Perl syntax.  The documentation shows the complete
syntax of the forms headed by the keyword.  The complete form may be
either a statement or an expression, as indicated in the documentation.
The keyword is only recognised if it appears as a bareword at the start
of a statement/expression.

=head2 Direct escape continuation access

This facility provides direct access to the continuation functions/objects
implemented by L<Scope::Escape>, referenced through lexically-scoped
variables.  It is just slightly more structured than direct use of
L<Scope::Escape>'s operators.

In each version, there is a code block and a variable I<ESCAPE_VAR>.
I<ESCAPE_VAR> is a lexically-scoped (C<my>-like) scalar variable.
Its name must start with a C<$> sigil, and must not include package
qualification.  I<ESCAPE_VAR> will be defined lexically, being visible
in the code textually contained within the block.  Its value will be a
reference to an escape continuation targetting the block.  Calling the
continuation as a function will result in the code block exiting,
returning the values that were passed to the continuation.

Do not assign a new value to I<ESCAPE_VAR>.  In this version of this module,
I<ESCAPE_VAR> behaves like a normal writable variable, but this is an
implementation accident and may change in a future version.

=over

=item with_escape_function ESCAPE_VAR;

This form is a complete statement, ending with semicolon.
I<ESCAPE_VAR> is lexically defined within the enclosing block (from
this statement to the end of the block), and contains a reference to an
unblessed escape function for the enclosing block.

=item with_escape_function ESCAPE_VAR BLOCK

This form is a complete statement, ending with the closing brace of
I<BLOCK>.  I<BLOCK> is executed normally.
I<ESCAPE_VAR> is lexically defined within I<BLOCK>, and contains a
reference to an unblessed escape function for the I<BLOCK>.

=item with_escape_function(ESCAPE_VAR BLOCK)

This form is an expression.  I<BLOCK> is executed normally, and its
return value will become the value of this expression.
I<ESCAPE_VAR> is lexically defined within I<BLOCK>, and contains a
reference to an unblessed escape function for the I<BLOCK>.

=item with_escape_continuation ESCAPE_VAR;

This form is a complete statement, ending with semicolon.
I<ESCAPE_VAR> is lexically defined within the enclosing block (from
this statement to the end of the block), and contains a reference to a
blessed escape continuation for the enclosing block.

=item with_escape_continuation ESCAPE_VAR BLOCK

This form is a complete statement, ending with the closing brace of
I<BLOCK>.  I<BLOCK> is executed normally.
I<ESCAPE_VAR> is lexically defined within I<BLOCK>, and contains a
reference to a blessed escape continuation for the I<BLOCK>.

=item with_escape_continuation(ESCAPE_VAR BLOCK)

This form is an expression.  I<BLOCK> is executed normally, and its
return value will become the value of this expression.
I<ESCAPE_VAR> is lexically defined within I<BLOCK>, and contains a
reference to a blessed escape continuation for the I<BLOCK>.

=back

=head2 Returnable blocks with lexically-scoped names

This facility provides lexical scoping of names for non-locally
returnable blocks, while avoiding visible reification of continuations.
(C<with_escape_function> and C<with_escape_continuation> provide the
same lexical scoping, but reify the continuations and put the lexical
names in the ordinary scalar variable namespace.)

In each version, there is a code block which is labelled with a static
bareword identifier I<TAG>.  The tag is lexically scoped, being visible
in the code textually contained within the block.  The C<return_from>
keyword can then be used to return from the textually enclosing block
with a specified tag.

In Common Lisp (the model for these special forms), there are many
implicit returnable blocks, in addition to the explicit ones established
by the C<block> operator.  Most notably, the body of each C<defun>-defined
function is a returnable block tagged with the function's name.
This module does not perceive any such implicit blocks: a C<return_from>
form will only return from a block explicitly established with C<block>.

=over

=item block TAG;

This form is a complete statement, ending with semicolon.
The enclosing block (from this statement to the end of the block) is
returnable, tagged with I<TAG>.

=item block TAG BLOCK

This form is a complete statement, ending with the closing brace of
I<BLOCK>.  I<BLOCK> is executed normally.
I<BLOCK> is returnable, tagged with I<TAG>.

=item block(TAG BLOCK)

This form is an expression.  I<BLOCK> is executed normally, and its
return value will become the value of this expression.
I<BLOCK> is returnable, tagged with I<TAG>.

=item return_from TAG VALUE ...

=item return_from(TAG VALUE ...)

This form is an expression.  It transfers control to exit from the
lexically enclosing returnable block tagged with I<TAG>.  If there is
no matching block, it is a compile-time error.  Zero or more I<VALUE>s
may be supplied, which will be returned from the block.  (Each I<VALUE>
is stated as an expression, which is evaluated normally.)

Due to limitations of the API available to add-on parsing code, the
form without parentheses is only available when it is the first thing
in a statement.

=back

=head2 Catch blocks with dynamically-scoped names

This facility provides dynamic scoping of names for non-locally
returnable blocks, while avoiding visible reification of continuations.
The blocks can "catch" values that are "thrown" by lexically-remote code.
(There is some resemblance here to throwing and catching of exceptions,
but this is not an exception mechanism in itself.)

In each version, there is a code block which is labelled with a (possibly
runtime-generated) string identifier I<TAG>.  In the C<catch> form,
I<TAG> must be stated as a double-quoted or single-quoted string syntax,
possibly including variable interpolation.  The tag is dynamically scoped,
being visible during the execution of the block.  The C<throw> function
can then be used to return from (throw a value to) the dynamically
enclosing block (the catch block) with a specified tag.

The Common Lisp C<catch> and C<throw> operators allow any object to
be used as a catch tag, and the tags are compared for object identity.
This allows code to generate a catch tag that is guaranteed to be unique,
simply by using a newly-allocated cons cell or similar object that is
not referenced from anywhere else.  If that sort of semantic is required,
it is best implemented by using the C<with_escape_function> operator and
saving the continuation reference in a C<local>ised global variable.
It is more usual for Common Lisp catch tags to be symbols, which
idiomatically correspond to Perl strings, compared for string equality.

=over

=item catch TAG;

This form is a complete statement, ending with semicolon.
The enclosing block (from this statement to the end of the block) is a
catch block, tagged with I<TAG>.

=item catch TAG BLOCK

This form is a complete statement, ending with the closing brace of
I<BLOCK>.  I<BLOCK> is executed normally.
I<BLOCK> is a catch block, tagged with I<TAG>.

=item catch(TAG BLOCK)

This form is an expression.  I<BLOCK> is executed normally, and its
return value will become the value of this expression.
I<BLOCK> is a catch block, tagged with I<TAG>.

=item throw(TAG, VALUE ...)

This is a function; all arguments are evaluated normally.  It transfers
control to exit from the dynamically enclosing catch block tagged
with I<TAG>.  If there is no matching block, it is a runtime error.
(Currently signalled by C<die>, but this may change in the future.)
Zero or more I<VALUE>s may be supplied, which will be returned from the
catch block.

=back

=head1 BUGS

The constructs that declare lexically-scoped variables do not generate
the "masks earlier declaration" warnings that they should.

Due to limitations of the API available to add-on parsing code, some
of the keywords are implemented by rewriting the source for the normal
Perl parser to parse.  This process risks unwanted interaction with
other syntax-mutating modules.  The resulting failures are likely to be
rather mystifying.

The lexical variable defined by C<with_escape_function> and
C<with_escape_continuation> is writable.  It really ought to be read-only.

Due to the aforementioned limitations of the API available to add-on
parsing code, the version of C<return_from> without parentheses is
only available when it is the first thing in a statement.  Since a
C<return_from> expression never returns locally, there is little reason
for it to be a subexpression anyway.

=head1 SEE ALSO

L<Scope::Escape>

=head1 AUTHOR

Andrew Main (Zefram) <zefram@fysh.org>

=head1 COPYRIGHT

Copyright (C) 2010 Andrew Main (Zefram) <zefram@fysh.org>

=head1 LICENSE

This module is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1;
