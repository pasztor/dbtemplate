package DbTemplate::CGI;

use strict;
use DbTemplate;

use Exporter();

our $template;
our $templatedir;

our @ISA = qw(Exporter);

sub init() {
	if(! DbTemplate->init($_[1])) {
		print DbTemplate::HTML->renderError('Hiba Történt','Hiba!',$DbTemplate::errstr);
		exit 0;
	}
	if ($ENV{AUTH_TYPE} ne "Basic" and defined($config->{reqauth}) and $config->{reqauth} == 1 ) {
		print DbTemplate::HTML->renderError('Auth Required','Hiba!','A konfiguráció szerint be kellene jelentkezni, de nincs beléptetés konfigurálva.');
		exit 0;
	}
	if (defined($config->{reqssl}) and $config->{reqssl} == 1 and $ENV{HTTPS} ne 'on' ) {
		print DbTemplate::HTML->renderError('SSL Required','Hiba!','A konfiguráció szerint csak https-el érhető el az oldal.');
		exit 0;
	}
	foreach my $i (split(/&/,$ENV{QUERY_STRING})) {
		my ($name,$val)=split(/=/,$i);
		$val=~s/\+/ /g;
		$val=~s/%([a-fA-F0-9][a-fA-F0-9])/pack('c',hex($1))/ge;
		$DbTemplate::params{$name}=$val;
	}
	if($ENV{REQUEST_METHOD} eq 'POST') {
		while(<>) {
			foreach my $i (split(/&/,$_)) {
				my ($name,$val)=split(/=/,$i);
				$val=~s/\+/ /g;
				$val=~s/%([a-fA-F0-9][a-fA-F0-9])/pack('c',hex($1))/ge;
				$DbTemplate::envpars{post}{$name}=$val;
			}
		}
	}
	$DbTemplate::envpars{user}=$ENV{REMOTE_USER};
	$DbTemplate::envpars{abspath}=$ENV{SCRIPT_NAME};
	return 1;
}

sub run() {
	if ( $ENV{QUERY_STRING} eq 'css' ) {
		print "Content-type: text/css\n\n".DbTemplate::HTML->getCssFile();
	} elsif ( $ENV{QUERY_STRING} eq 'debug=1') {
		print "Content-type: text/html\n\n";
		foreach my $i (keys(%{$DbTemplate::envpars{post}})) {
			print $i."=".$DbTemplate::envpars{post}{$i}."<br>\n";
		}
#	} elsif ( $ENV{QUERY_STRING} =~m/refreshrender=([0-9]+)&template=(.*)/) {
	} elsif ( defined($DbTemplate::params{refreshrender}) ) {
		print "Content-type: text/html\npragma: no-cache\n\n";
		DbTemplate->loadTemplate($DbTemplate::params{template});
		if ($ENV{REQUEST_METHOD} eq 'POST') {
			$config->{maintail}.=
			print "<div id=\"refreshresponse\" style=\"visibility : hidden\">\n";
			print DbTemplate->formFeed($template->{renderings}[$DbTemplate::envpars{post}{formseq}]);
			print "</div>\n";
		}
		print DbTemplate::HTML->renderElement($template->{renderings}[$DbTemplate::params{refreshrender}],$DbTemplate::params{refreshrender});
	} elsif ( defined($DbTemplate::params{genlistform}) ) {
		print "Content-type: text/html\npragma: no-cache\n\n";
		DbTemplate->loadTemplate($DbTemplate::params{template});
		print DbTemplate::HTML->renderList($template->{renderings}[$DbTemplate::params{genlistform}],$DbTemplate::params{genlistform});
	} else {
		print "Content-type: text/html\npragma: no-cache\n\n";
		DbTemplate->loadTemplate($DbTemplate::params{template});
		if ($ENV{REQUEST_METHOD} eq 'POST') {
			$config->{maintail}.=
			DbTemplate->formFeed($template->{renderings}[$DbTemplate::envpars{post}{formseq}]);
		}
		$config->{maintail}.='<div id="debugfield"></div>';
		print DbTemplate::HTML->renderPage();
	}
	return 1;
}

sub final() {
	return DbTemplate->final();
}

our @EXPORT = qw($template $templatedir);

1;
