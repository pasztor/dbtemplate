package DbTemplate::TextGen;

use strict;
use DbTemplate;

use Exporter();

our $template;
our $templatedir;

our @ISA = qw(Exporter);

sub init() {
	if(! DbTemplate->init($_[1])) {
		die 'Hiba történt:'.$DbTemplate::errstr."\n";
		exit 0;
	}
	return 1;
}

sub run() {
	my $self=shift;
	$DbTemplate::params{template}=shift;
	$DbTemplate::params{pkey}=shift;
	DbTemplate->loadTemplate($DbTemplate::params{template});
	print DbTemplate::Text->renderText();
	return 1;
}

sub final() {
	return DbTemplate->final();
}

our @EXPORT = qw($template $templatedir);

1;
