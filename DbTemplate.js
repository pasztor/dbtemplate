<script type="text/javascript">

function editorscript (fname,divname,rendseq,pkey,fno,fval,ftype,expars) {
	x=document.getElementById(divname);
	y=x.innerHTML;
	x.innerHTML='';
	x.innerHTML+='<form action="javascript:updatescript(\''+fname+'\',\''+expars+'\');" name="'+fname+'">'
	+'<input type="hidden" name="formseq" value="'+rendseq+'">'
	+'<input type="hidden" name="pkey" value="'+pkey+'">'
	+'<input type="hidden" name="fno" value="'+fno+'">'
	+'<input type="'+ftype+'" name="fval" value="'+fval+'">'
	+'</form>';
}

function Async ()
{
}

Async.request = function()
{
	var async;
	try {
		async=new ActiveXObject("Msxml2.XMLHTT");
	} catch(_) {
		try {
			async=new XMLHttpRequest();
		} catch(_) {
			return null;
		}
	}

	return async;
}

function updatescript (formname,expars) {
	var req;
	var mf;
	var renderseq;
	req=Async.request();
	mf=document.forms.namedItem(formname);
	renderseq=mf.formseq.value;
//	req.open('POST','@SELFREF@?debug',true);
	req.open('POST','@SELFREF@?refreshrender='+renderseq+'&template=@TEMPLATE@'+expars,true);
	req.onreadystatechange=function() {
		if (req.readyState==4) {
			var d;
			var df;
			d=document.getElementById('render'+renderseq);
			d.innerHTML=req.responseText;
			df=document.getElementById('refreshresponse');
			d=document.getElementById('debugfield');
			d.innerHTML=df.innerHTML;
			d=document.getElementById('render'+renderseq);
			d.removeChild(df);
		}
	}
	req.setRequestHeader('Content-Type','application/x-www-form-urlencoded; charset=utf-8');
	req.send('formname='+formname+ 
		'&action=update'+
		'&formseq='+mf.formseq.value+ 
		'&pkey='+mf.pkey.value+
		'&fno='+mf.fno.value+
		'&fval='+encodeURIComponent(mf.fval.value));
}

function listform(formid,divid,renderseq,fno,fval,pkey) {
	var req;
	req=Async.request();
	req.open('GET','@SELFREF@?genlistform='+renderseq+'&template=@TEMPLATE@'
		+'&fno='+fno+'&fval='+fval+'&formid='+formid+'&pkey='+pkey);
	req.onreadystatechange=function() {
		if(req.readyState==4) {
			var d;
			d=document.getElementById(divid);
			d.innerHTML=req.responseText;
		}
	}
	req.send();

}

function updateform(formid) {
	var req;
	var e;
	req=Async.request();
	e=document.forms.namedItem(formid);
	req.open('GET','@SELFREF@?genlistform='+e.formseq.value+'&template=@TEMPLATE@'
		+'&fno='+e.fno.value+'&fval='+e.fval.value+'&formid='+formid
		+'&search='+e.search.value+'&pkey='+e.pkey.value);
	req.onreadystatechange=function() {
		if(req.readyState==4) {
			var d;
			d=document.forms.namedItem(formid);
			d=d.parentNode;
			d.innerHTML=req.responseText;
		}
	}
	req.send();
}


function delrec (renderseq,name,pkey) {
	var req;
//	var mf;
	req=Async.request();
	req.open('POST','@SELFREF@?refreshrender='+renderseq+'&template=@TEMPLATE@',true);
	req.onreadystatechange=function() {
		if (req.readyState==4) {
			var d;
			var df;
			d=document.getElementById('render'+renderseq);
			d.innerHTML=req.responseText;
			df=document.getElementById('refreshresponse');
			d=document.getElementById('debugfield');
			d.innerHTML=df.innerHTML;
			d=document.getElementById('render'+renderseq);
			d.removeChild(df);
		}
	}
	req.setRequestHeader('Content-Type','application/x-www-form-urlencoded; charset=utf-8');
	req.send('pkey='+pkey+ 
		'&name='+name+
		'&formseq='+renderseq+
		'&action=delete');
}

function refreshrender (renderseq) {
	var req;
	req=Async.request();
	req.open('GET','@SELFREF@?refreshrender='+renderseq+'&template=@TEMPLATE@',true);
	req.onreadystatechange=function() {
		if (req.readyState==4) {
			var d;
			var df;
			d=document.getElementById('render'+renderseq);
			d.innerHTML=req.responseText;
			df=document.getElementById('refreshresponse');
			d=document.getElementById('debugfield');
			d.innerHTML=df.innerHTML;
			d=document.getElementById('render'+renderseq);
			d.removeChild(df);
		}
	}
	req.send();
}
</script>
