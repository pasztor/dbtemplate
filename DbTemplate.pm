package DbTemplate;

use strict;
use DBI;
use Exporter();
use Crypt::PasswdMD5;

our $template;
our $templatedir;
our $config;
our $dbh;
our $ref;
our $errstr;
our @sqlrestr;
our %params;
our %envpars;
our %uniqs;

our @ISA = qw(Exporter);

BEGIN {
	our $VERSION;
	$VERSION='$Date: 2009-08-13 11:37:43 $';
}

sub init () {
	shift;
	$templatedir=shift;
	@sqlrestr=();
	if (! do $templatedir."/.dtconf" ) {
		$errstr="Nem sikerült a konfigot beolvasni\n";
		return 0;
	}
	if (!($dbh=DBI->connect($config->{dbparams}->{ds},
			$config->{dbparams}->{user},
			$config->{dbparams}->{passw},
			$config->{dbparams}->{attr}))) {
		$errstr="Error connecting to the database: $DBI::errstr\n";
		return 0;
	}
	return 1;
}

sub loadTemplate() {
	shift;
	my $templatename=shift;
	if(defined($templatename)) {
		if ( $templatename =~ m/\./ ) {
			$template={
				pagetitle=>'Bad Templatename',
				renderings=>[{rendertype=>'simpletext',text=>'Rossz templatenév'}]
			};
		} elsif (-r $templatedir."/".$templatename and -f $templatedir."/".$templatename) {
			if (do $templatedir."/".$templatename) {
				$envpars{template}=$templatename;
			} else {
				$template={
					pagetitle=>'Template error',
					renderings=>[{rendertype=>'simpletext',text=>'Hibás template fájl'}]
				};
			}
		} else {
			$template={
				pagetitle=>'Template not found',
				renderings=>[{rendertype=>'simpletext',text=>'Nem találtam ilyen templatet'}]
			};
		}
	} elsif(defined($config->{defaulttemplate})) {
		if (-r $templatedir."/".$config->{defaulttemplate}) {
			if (do $templatedir."/".$config->{defaulttemplate}) {
				$envpars{template}=$config->{defaulttemplate};
			} else {
				$template={
					pagetitle=>'Template error',
					renderings=>[{rendertype=>'simpletext',text=>'Hibás template fájl'}]
				};
			}
		} else {
			$template={
				pagetitle=>'Default Template not found',
				renderings=>[{rendertype=>'simpletext',text=>'Nem találtam meg az alapértelmezett template-t'}]
			};
		}
	} else {
		$template={
			renderings=>[{rendertype=>'simpletext',text=>$config->{defaulttext}}]
		};
	}
	return 0;
}

sub query() {
	my $self=shift;
	my $render=shift;
	my $fields;
	my $ret='';
	my @que=();
	if ($render->{rendertype} eq 'tableview') {
		my @columns=map($_->{colname},@{${render}->{'columns'}});
		$fields=join(',',@columns);
		if (defined($render->{orderby})) { push @que,('ORDER','BY',$render->{orderby}); }
		$ref=$dbh->prepare(join(' ',('SELECT',$fields,'FROM',$render->{tablespec},@que)));
		$ref->execute() || return "Nem sikerült végrehajtani a lekérdezést: $DBI::errstr<br>\n";
	} elsif ($render->{rendertype} eq 'pkeyview') {
		$ref=$dbh->prepare($render->{query});
		$ref->execute($params{pkey}) || return "Nem sikerült végrehajtani a lekérdezést: $DBI::errstr<br>\n";
	}
	return $ret;
}

sub genVal() {
	my $self=shift;
	my $val=shift;
	my $column=shift;
	if(!defined($column->{enctype})) {
		return $val;
	} elsif($column->{enctype} eq 'cryptmd5') {
		if ($val=~m/^\$1\$/) { return $val; }
		return unix_md5_crypt($val,join('',('.','/','0'..'9','a'..'z','A'..'Z')[rand 64,rand 64,rand 64,rand 64,rand 64,rand 64,rand 64,rand 64]));
	}
	return $val;
}

sub formFeed() {
	my $self=shift;
	my $render=shift;
	my $ret="<hr>\n";
	my @columns;
	my $query;
	@columns=map(${$_}{colname},@{${render}->{'columns'}});
	if ($render->{rendertype} eq 'inputform') {
		if($render->{insertmode} eq 'strict') {
			$query=join(' ',('INSERT','INTO',$render->{tablespec},
						'(',join(', ',@columns),')',
						'VALUES','(',
						join(', ',map('?',@columns)),')'));
		} else {
			$query=join(' ',('INSERT','INTO',$render->{tablespec},
						'VALUES','(',
						join(', ',map('?',@columns)),')'));
		}
		$ref=$dbh->prepare($query);
		if($ref->execute(map(DbTemplate->genVal($envpars{post}{$_->{colname}},$_), @{${render}->{'columns'}}))) {
			$ret.='successfull insert';
		} else {
			$ret.='Error in insert:'.$DBI::errstr;
		}
		$dbh->commit();
		if(ref($render->{inserthook}) eq 'CODE') {
			$ret.=$render->{inserthook}($render,\%envpars,$dbh);
		}
		if ( defined($config->{postdebug}) ) {
			$ret.="<br>\n".$query;
		}
		$ret.="<br>\n";
	}
	if ($render->{rendertype} eq 'multiinput') {
		foreach my $i (@{$render->{'statements'}}) {
			$ref=$dbh->prepare($i->{sql});
			if($ref->execute(map($envpars{post}{$_},@{$i->{params}}))) {
				$ret.='successfull insert';
			} else {
				$ret.='Error in insert:'.$DBI::errstr;
			}
			if(defined($i->{serial})) {
				$envpars{post}{$i->{serial}}=
					$dbh->last_insert_id(undef,undef,undef,undef,{sequence=>$i->{serial}});
			}
			$dbh->commit();
			if(ref($render->{inserthook}) eq 'CODE') {
				$ret.=$render->{inserthook}($render,\%envpars,$dbh);
			}
			if ( defined($config->{postdebug}) ) {
				$ret.="<br>\n".$query;
			}
		}
	}
	if ($render->{rendertype} eq 'tableview' and $envpars{post}{action} eq 'delete') {
		$query=join(' ',('DELETE','FROM',
			(defined($render->{updatetable})?$render->{updatetable}:$render->{tablespec}),
			'WHERE',$envpars{post}{name},'=','?'));
		$ref=$dbh->prepare($query);
		if(ref($render->{deletehook}) eq 'CODE') {
			$ret.=$render->{deletehook}($render,\%envpars,$dbh);
		}
		if($ref->execute($envpars{post}{pkey})) {
			$ret.='succesfull delete';
		} else {
			$ret.='error in delete:'.$DBI::errstr;
		}
		$dbh->commit();
		$ret.="<br>\n";
	}
	if ($render->{rendertype} eq 'tableview' and $envpars{post}{action} eq 'update') {
		my $colname=$render->{columns}[$envpars{post}{fno}]{colname};
		my $pcolname=$render->{columns}[$render->{pkeycol}]{colname};
		$colname=~s/^.*\.//;
		$pcolname=~s/^.*\.//;
		if(defined($render->{columns}[$envpars{post}{fno}]{updatefield})) {
			$colname=$render->{columns}[$envpars{post}{fno}]{updatefield}; }
		$envpars{post}{fval}=DbTemplate->genVal($envpars{post}{fval},$render->{columns}[$envpars{post}{fno}]);
		$query=join(' ',('UPDATE',
			(defined($render->{updatetable})?$render->{updatetable}:$render->{tablespec}),
			'SET',$colname,'=','?',
			'WHERE',$pcolname,'=','?'));
		$ref=$dbh->prepare($query);
		if($ref->execute($envpars{post}{fval},$envpars{post}{pkey})) {
			$ret.='successfull update';
		} else {
			$ret.='error in update:'.$DBI::errstr;
		}
		$dbh->commit();
		$ret.=$query;
		if(ref($render->{columns}[$envpars{post}{fno}]{updatehook}) eq 'CODE') {
			$ret.=$render->{columns}[$envpars{post}{fno}]{updatehook}($render,\%envpars,$dbh);
		}
		$ret.="<br>\n";
	}
	if ($render->{rendertype} eq 'pkeyview' and $envpars{post}{action} eq 'update') {
		my $colname=$render->{columns}[$envpars{post}{fno}]{colname};
		my $pcolname=$render->{columns}[$render->{pkeycol}]{colname};
		$colname=~s/^.*\.//;
		$pcolname=~s/^.*\.//;
		if(defined($render->{columns}[$envpars{post}{fno}]{updatefield})) {
			$colname=$render->{columns}[$envpars{post}{fno}]{updatefield}; }
		$envpars{post}{fval}=DbTemplate->genVal($envpars{post}{fval},$render->{columns}[$envpars{post}{fno}]);
		$query=join(' ',('UPDATE',$render->{updatetable},
			'SET',$colname,'=','?',
			'WHERE',$pcolname,'=','?'));
		$ref=$dbh->prepare($query);
		if($ref->execute($envpars{post}{fval},$envpars{post}{pkey})) {
			$ret.='successfull update';
		} else {
			$ret.='error in update:'.$DBI::errstr;
		}
		$dbh->commit();
		$ret.=$query;
		if(ref($render->{columns}[$envpars{post}{fno}]{updatehook}) eq 'CODE') {
			$ret.=$render->{columns}[$envpars{post}{fno}]{updatehook}($render,\%envpars,$dbh);
		}
		$ret.="<br>\n";
		
	}
	if ($render->{rendertype} eq 'pkeyview' and $envpars{post}{action} eq 'delete') {
		$query=join(' ',('DELETE','FROM', $render->{updatetable},
			'WHERE',$envpars{post}{name},'=','?'));
		$ref=$dbh->prepare($query);
		if(ref($render->{deletehook}) eq 'CODE') {
			$ret.=$render->{deletehook}($render,\%envpars,$dbh);
		}
		if($ref->execute($envpars{post}{pkey})) {
			$ret.='succesfull delete';
		} else {
			$ret.='error in delete:'.$DBI::errstr;
		}
		$dbh->commit();
		$ret.="<br>\n";
	}
	if ( defined($config->{postdebug}) ) {
		$ret.="POST-debug:<br>\n";
		foreach my $i (keys(%{$envpars{post}})) {
			$ret.=$i.'=='.$envpars{post}{$i}."<br>\n";
		}
	}
	return $ret;
}

sub ugen() {
	my $self=shift;
	my $name=shift;
	if(defined($uniqs{$name})) {
		$uniqs{$name}++;
		return $name.$uniqs{$name};
	} else {
		$uniqs{$name}=0;
		return $name."0";
	}
}

sub final() {
	$dbh->commit();
	$dbh->disconnect();
}

our @EXPORT = qw($template $templatedir $config);

1;

package DbTemplate::HTML;

use strict;
use Exporter();
use URI::Escape;
use DBI;
use POSIX qw(strftime);

our @ISA = qw(Exporter);

# Give the style information
sub getStyle() {
	my $css='';
	if(defined($config->{splitcss})) {
		$css.="<link rel=\"STYLESHEET\" type=\"text/css\" href=\"".$envpars{abspath}."?css\" title=\"dbtemplatestyle\">\n<style>\n";
	} else {
		$css.="<style>\n".getCssFile();
	}
	if(defined($config->{style})) { $css.=$config->{style}; }
	if(defined($template->{style})) { $css.=$template->{style}; }
	$css.="</style>\n";
	return $css;
}

sub getCssFile () {
	my $css;
	foreach my $i (@INC) {
		if (-r $i."/"."DbTemplate.css") {
			my $isave=$/;
			undef $/;
			open F,$i."/"."DbTemplate.css";
			$css=<F>;
			close F;
			$/=$isave;
			last;
		}
	}
	return $css;
}

sub getJsFile () {
	my $js;
	foreach my $i (@INC) {
		if (-r $i."/"."DbTemplate.js") {
			my $isave=$/;
			undef $/;
			open F,$i."/"."DbTemplate.js";
			$js=<F>;
			close F;
			$/=$isave;
			last;
		}
	}
	$js=~s/\@SELFREF\@/$envpars{abspath}/g;
	$js=~s/\@TEMPLATE\@/$envpars{template}/g;
	return $js;
}

# render an error page
sub renderError() {
	my $self=shift;
	my $title=shift;
	my $warntext=shift;
	my $explain=shift;
	my $ret="Content-type: text/html\n\n";
	undef $config->{splitcss};
	$ret.="<html><head><title>".$title."</title>\n";
	$ret.=getStyle();
	$ret.="</head>\n<body>\n";
	$ret.="<h1 class=\"error\">".$warntext."</h1>\n";
	$ret.="<div class=\"error\">".$explain."</div><br>\n";
	$ret.="<div class=\"footer\">".renderVer()."</div>\n";
	$ret.="</body>\n</html>";
	return $ret;
}

# complete HTML rendering function
sub renderPage() {
	my $self=shift;
	my $abspath=$envpars{abspath};
	my $subsite=(defined($template->{pagetitle})?$template->{pagetitle}:'');
	my $titleprefix=(defined($config->{titleprefix})?$config->{titleprefix}:'DbTemplate :: ');
	my $ret='';

	# Render HTML HEAD
	$ret.="<html>\n<head>\n";
	$ret.="<title>".$titleprefix.$config->{site}.(defined($envpars{template})? " :: ".$subsite:'')."</title>\n";
	if(defined($config->{head})) { $ret.=$config->{head}."\n"; }
	if(defined($template->{head})) { $ret.=$template->{head}."\n"; }
	$ret.=getStyle();
	$ret.=getJsFile();
	$ret.="</head>\n";

	# Render HTML BODY
	$ret.="<body>\n";
	if(defined($config->{bodystart})) { $ret.=$config->{bodystart}."\n"; }
	$ret.="<table class=\"main\">\n<tr>\n";
	$ret.="<td>\n".renderMenu()."</td>\n";
	$ret.="<td>\n".renderMain()."</td>\n</tr>\n";
	$ret.="<tr>\n".renderFooter()."\n</tr>\n";
	$ret.="</table>\n</body>\n</html>\n";
	return $ret;
}

# Menu rendering function
sub renderMenu () {
	my $ret='';
	if (defined($config->{menuhead})) { $ret.=$config->{menuhead}."\n"; }
	$ret.="<table class=\"menu\">\n";
	$ret.="<caption>".(defined($config->{menutext})?$config->{menutext}:'Menu')."</caption>\n";
	opendir D,$templatedir;
	my @d=grep { /^[^\.]+$/ && -r $templatedir."/".$_ && -f $templatedir."/".$_ } readdir(D);
	foreach my $i (@d) {
		if(ref($config->{menurender}) eq 'CODE') {
			$ret.=$config->{menurender}($envpars{abspath},$i);
		} else {
			$ret.= "<tr><td><a href=\"".
				$envpars{abspath}."?template=".uri_escape($i)."\">".
				(defined($config->{menumap}{$i})?$config->{menumap}{$i}:$i).
				"</a></td></tr>\n";
		}
	}
	closedir(D);
	if (defined($config->{menutail})) { $ret.= $config->{menutail}."\n"; }
	$ret.= "</table>\n";
	return $ret;
}

# Render the page's Main content
sub renderMain() {
	my $ret='';
	my $subsite=(defined($template->{pagetitle})?$template->{pagetitle}:'');

	if (defined(${config}->{mainhead})) {$ret.=${config}->{mainhead};}
	if (defined($envpars{template})) {$ret.="<h1 class=\"query\">".$subsite."</h1>\n"; } 
	if (defined(${template}->{renderings})) {
		my @tables=();
		my $fs=0;
		foreach my $i (@{${$template}{renderings}}) {
			my $r=DbTemplate::HTML->renderElement($i,$fs);
			if (defined($r)) { push @tables,'<div id="render'.$fs.'">'.$r.'</div>'; }
			$fs++;
		}
		$ret.=join("<hr class=\"query\">\n",@tables);
	} else {
		$ret.="This template doesn't contain any element to show\n";
	}
	if (defined(${config}->{maintail})) {$ret.=${config}->{maintail};}
	return $ret;
}

sub renderElement() {
	my $self=shift;
	my $rend=shift;
	my $fs=shift;
	my $t='';
	if (defined($params{pkey}) and defined($rend->{showonpkey}) and !$rend->{showonpkey}) {
		return undef;
	}
	$rend->{formseq}=$fs;
	$t.="<table class=\"query\" border=\"3\">\n";
	$t.="<caption>".(defined($rend->{title})?$rend->{title}:'')."</caption>\n";
	if (not defined($rend->{rendertype})) {
		$t.="<!--Undefined rendertype-->\n";
	} elsif ($rend->{rendertype} eq 'simpletext') {
		$t.=$rend->{text};
	} elsif ($rend->{rendertype} eq 'tableview') {
		$t.="<thead><tr>\n";
		foreach my $j (@{${$rend}{'columns'}}) {
			$t.="<th".(defined(${$j}{title})?' title="'.${$j}{title}.'">':'>').${$j}{description}."</th>";
		}
		$t.="</tr></thead>\n";
		$t.=DbTemplate->query($rend);
		if (defined($ref)) {
			$t.=renderTableView($rend);
		}
	} elsif ($rend->{rendertype} eq 'inputform' or $rend->{rendertype} eq 'multiinput') {
		$t.=DbTemplate->query($rend);
		$t.="<form method=\"POST\" action=\"".$envpars{abspath};
		$t.="?template=".uri_escape($envpars{template})."\" formname=\"render".$fs."form\">";
		$t.="<input type=\"hidden\" name=\"formseq\" value=\"".$fs."\" />";
		if($rend->{rendertype} eq 'multiinput' and defined($DbTemplate::params{pkey})) {
			$t.="<input type=\"hidden\" name=\"pkey\" value=\"".$DbTemplate::params{pkey}."\" />";
		}
		$t.="<thead><tr>\n";
		$t.="<th>mező</th><th>érték</th>\n";
		$t.="<tfoot><tr><td colspan=\"2\"><input type=\"submit\" value=\"Küld\" /></td></tr></tfoot>\n";
		$t.="</tr></thead>\n";
		foreach my $j (@{${$rend}{'columns'}}) {
			$t.="<tr><td>".${$j}{description}."</td>";
			$t.="<td><input name=\"".${$j}{colname}."\" /></td></tr>\n";
		}
		$t.="</form>\n";
	} elsif ($rend->{rendertype} eq 'pkeyview') {
		if (! defined($params{pkey})) {
			return undef;
		}
		$t.="<thead><tr>\n";
		foreach my $j (@{${$rend}{'columns'}}) {
			$t.="<th>".${$j}{description}."</th>";
		}
		$t.="</tr></thead>\n";
		$t.=DbTemplate->query($rend);
		if (defined($ref)) {
			$t.=renderTableView($rend);
		}
	}
	$t.="</table>\n";
	return $t;
};

# Egyszerű táblázat lekérdezés
sub renderTableView() {
	my $rend=shift;
	my $ret='';
	my $aref=$ref->fetchall_arrayref();
	my $rn=0;
	for (my $i=0; $i <= $#{$rend->{columns}} ; $i++ ) {
		if(defined($rend->{columns}[$i]{restricted}) and $rend->{columns}[$i]{restricted}==1) {
			if(not defined($rend->{columns}[$i]{restricttype})) {
			} elsif ($rend->{columns}[$i]{restricttype} eq 'static') {
				if (grep { $_ eq $envpars{user} } @{$rend->{columns}[$i]{restrictlist}}) {
					$rend->{columns}[$i]{restricted} = 0;
				}
			} elsif ($rend->{columns}[$i]{restricttype} eq 'byselect') {
				$ref=$dbh->prepare($rend->{columns}[$i]{restrictquery});
				$ref->execute($envpars{user});
				if ($ref->rows() >0) {
					$rend->{columns}[$i]{restricted} = 0;
				}
			}
		}
	}
	foreach my $row ( @{$aref} ) {
		my @row=map($_,@{$row});
		for (my $i=0 ; $i<= $#row ; $i++) {
			my $t=$row[$i];
			if(defined($rend->{columns}[$i]{restricted}) and $rend->{columns}[$i]{restricted}==1) {
				$row[$i]=$rend->{columns}[$i]{restricttext};
			}
			if(defined($rend->{columns}[$i]{editable}) and $rend->{columns}[$i]{editable}==1) {
				my $formid=DbTemplate->ugen("form");
				my $divid=DbTemplate->ugen("div");
				$row[$i]="<div ondblclick=\"javascript:editorscript("
					."'".$formid."','".$divid."',"
					.$rend->{formseq}.","
					."'".${$row}[$rend->{pkeycol}]."',"
					.$i.","
					."'".$t."',"
					."'text',".($rend->{rendertype} eq 'pkeyview'?"'&pkey=".$params{pkey}."'":"''")
					.");\" id=\"".$divid."\">".$t."&nbsp;</div>";
			}
			if(defined($rend->{columns}[$i]{editlist}) and $rend->{columns}[$i]{editlist}==1) {
				my $formid=DbTemplate->ugen("form");
				my $divid=DbTemplate->ugen("div");
				$row[$i]="<div ondblclick=\"javascript:listform("
					."'".$formid."','".$divid."',"
					.$rend->{formseq}.","
					.$i.","
					."'".(defined($rend->{columns}[$i]{defvalfield})?${$row}[$rend->{columns}[$i]{defvalfield}]:$t)
					."','".${$row}[$rend->{pkeycol}]."');\" id=\"".$divid."\">".$t."&nbsp;</div>";
			}
			if(defined($rend->{columns}[$i]{delete}) and $rend->{columns}[$i]{delete}==1) {
				$row[$i]="<a href=\"javascript:delrec(".$rend->{formseq}.",'";
				$row[$i].=$rend->{columns}[$i]{colname}."','".$t."');\">X</a>";
			}
			if(defined($rend->{columns}[$i]{pkeylink}) and $rend->{columns}[$i]{pkeylink}==1) {
				$row[$i]="<a href=\"".$envpars{abspath}."?template="
					.uri_escape(defined($rend->{columns}[$i]{pkeytemplate})?
								$rend->{columns}[$i]{pkeytemplate}:
							(defined($rend->{pkeytemplate})?
								$rend->{pkeytemplate}:
								$envpars{template}))
					."&pkey="
					.uri_escape(${$row}[$rend->{pkeycol}])."\">".$t."</a>";
			}
		}
		if(defined($rend->{fillempty}) and $rend->{fillempty} == 1) {
			for (my $i=0 ; $i<= $#row ; $i++) {
				if(not defined($row[$i])) { $row[$i]='&nbsp;'; }
			}
		}
		$ret.="<tr class=\"trc".($rn%2)."\"><td>".join('</td><td>',@row)."</td></tr>\n";
		#$ret.="<tr><td>".join('</td><td>',@row)."</td></tr>\n";
		$rn++;
	}
	return $ret;
}

# Egyszerű input form
sub renderInputForm() {
}

sub renderList() {
	my $self=shift;
	my $rend=shift;
	my $fs=shift;
	my $query;
	my $t='';
	my @q=();
	my @p=();
	$t.="<form method=\"POST\" name=\"".$params{formid}."\" action=\"".$envpars{abspath};
	$t.="?template=".uri_escape($envpars{template})."\">\n";
	$t.="<input type=\"hidden\" name=\"formseq\" value=\"".$fs."\" />\n";
	$t.="<input type=\"hidden\" name=\"fno\" value=\"".$params{fno}."\" />\n";
	$t.="<input type=\"hidden\" name=\"pkey\" value=\"".$params{pkey}."\" />\n";
	if(defined($rend->{columns}[$params{fno}]{searchfield})) {
		$t.="<input type=\"text\" name=\"search\" value=\"".$params{search}.
			"\" onChange=\"javascript:updateform('".$params{formid}."');\">\n";
	}
	$t.="<select name=\"fval\">\n";
	@q=('SELECT',join(',',@{$rend->{columns}[$params{fno}]{listfields}}));
	push(@q,'FROM',$rend->{columns}[$params{fno}]{listtable});
	if(defined($params{search})) {
		push(@q,'WHERE',${$rend->{columns}[$params{fno}]{listfields}}[1].' ~* ?');
		@p=($params{search});
	}
	$ref=$dbh->prepare(join(' ',@q));
	if($ref->execute(@p)) {
		while(my @r= $ref->fetchrow_array) {
			$t.="<option value=\"".$r[0]."\""
				.($r[0] eq $params{fval}?' selected ':'').">".$r[1]."</option>\n";
		}
	} else {
		$t.="Nem sikerült végrehajtani a lekérdezést: $DBI::errstr<br>\n";
	}
	$t.="</select>\n";
	$t.="<input type=\"button\" onClick=\"javascript:updatescript('".$params{formid}."','');\" value=\"OK\">";
	$t.="</form>\n";
	return $t;
}

# Csoporttagság-kezelő
sub renderGroupMembership() {
}

sub renderFooter() {
	my $ret='';
	$ret.="<td colspan=\"2\" class=\"footer\">\n";
	$ret.=(defined($envpars{user})?"Belépve: ".$envpars{user}:"Nincs bejelentkezve")."<br>\n";
	$ret.=renderVer()."\n</td>";
	return $ret;
}

sub renderVer() {
	return "<small>DbTemplate Engine -".$DbTemplate::VERSION."<br>".(strftime "%Y %b %e %H:%M:%S", localtime)."</small>";
}
our @EXPORT=qw();

1;

package DbTemplate::Text;

use strict;
use Exporter();

our @ISA = qw(Exporter);

sub renderText() {
	my $self=shift;
	my $ret='';
	if (defined($template->{renderings})) {
		my $fs=0;
		foreach my $i (@{${$template}{renderings}}) {
			$ret.=DbTemplate::Text->renderElement($i,$fs);
			$fs++;
		}
	} else {
		$ret.="This template doesn't contain any element to show\n";
	}
	return $ret;
}

sub renderElement() {
	my $self=shift;
	my $rend=shift;
	my $fs=shift;
	my $t='';
	if (not defined($rend->{rendertype})) {
		$t.="Not defined rendertype: $fs\n";
	} elsif ($rend->{rendertype} eq 'simpletext') {
		$t.=$rend->{text};
	} elsif ($rend->{rendertype} eq 'tableview') {
		$t.=DbTemplate->query($rend);
		if (defined($ref)) {
			$t.=renderTableview($rend);
		}
	} elsif ($rend->{rendertype} eq 'pkeyview') {
		my $oldpkey=$params{pkey};
		if (defined($rend->{pkey})) {
			$params{pkey}=$rend->{pkey};
		}
		$t.=DbTemplate->query($rend);
		if (defined($ref)) {
			$t.=renderTableView($rend);
		}
		$params{pkey}=$oldpkey;
	}
	return $t;
}

sub renderTableView() {
	my $rend=shift;
	my $ret='';
	my $aref=$ref->fetchall_arrayref();
	foreach my $row (@{$aref} ) {
		my @row=map($_,@{$row});
		my $temp=$rend->{text};
		for (my $i=0; $i<= $#row; $i++) {
			$temp=~s/__${i}__/$row[$i]/g;
			
		}
		$ret.=$temp;
	}
	return $ret;
}

our @EXPORT=qw();

1;
