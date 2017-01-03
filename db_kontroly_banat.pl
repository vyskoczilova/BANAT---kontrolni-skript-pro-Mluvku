#!/usr/bin/perl
# Checks the format of the transcriptions, writes error messages to
# STDERR and fixed output to STDOUT.

use strict;
use warnings;
# use utf8;

# binmode(STDIN,":encoding(iso-8859-2)");
# binmode(STDOUT,":encoding(iso-8859-2)");
# binmode(STDERR,":encoding(iso-8859-2)");

#######################
# Odkomentovani tohoto cyklu zpusobi vyhnuti se vsem kontrolam.
# while (<STDIN>)
# {
#   print;
# }
# exit 0;
#######################

my $MAX_WORDS_IN_SEGMENT = 20;
my $MAX_ERR_LINES = 100;
my $err_text = "";
my $temp = "";
my $line_num = 0;
my $last_err_line_num = 0;

sub mydie($)
{
  if ($line_num != $last_err_line_num)
  {
    $last_err_line_num = $line_num;
#    $err_text .= "\n" if ($err_text ne "");
    $err_text .= "$_[0]";
    if (($err_text =~ tr/\n/\n/) >= $MAX_ERR_LINES)
    {
      die "$err_text";
    }
  }
}

my $fileID = substr($ARGV[0],0,7); # obsahuje 7 znaku ID sondy (napr. "07A157N")
my $sp_num = 0;
my $cur_sp;
my $last_sp = "-"; # hodnoty: "-" zacatek souboru
                   #          "|" prekryv ("|1", "|2" nebo "|3")
                   #          "_" neznamy mluvci ("_-" nebo "_(")
                   #          jinak vzdycky jmeno mluvciho (0, 1, 2 atd.)
                   #          muze byt pripojeno take E jako priznak chyby
undef my %spk; # hash mluvcich kde klice jsou ID podle databaze ("00", "01", "02" apod.)
undef my %idname; # hash mluvcich kde klice jsou transcriberove "spk1" "spk2" apod. a hodnoty "00", "01", "02" apod. (viz %spk)
undef my %spkmap; # mapovani ID mluvcich podle databaze (typu "01") na ID podle Karoliny Vyskocilove (typu "01-F79")

open(MLUVCI,"mluvci.csv") or die "Chyba: nelze otevrit soubor s mapovanim mluvcich!\n";
while (<MLUVCI>)
{ # cteni mapovani mluvcich tykajici se kontrolovaneho prepisu do %spkmap
  chomp;
  s/\r$//;
  (my $db_id,my $kv_id) = split(/;/);
  if (substr($db_id,0,7) eq $fileID)
  { # jde o mapovani tykajici se teto sondy
    $spkmap{substr($db_id,7,2)} = $kv_id;
  }
}
close(MLUVCI);

while (@ARGV)
{ # cteni definic mluvcich predanych z databaze
  $sp_num++;
  my $temp = substr(shift(@ARGV),7);
  my $kv_id = $spkmap{$temp} or die "Chyba: mluvci $temp nenalezen v mapovacim souboru\n";
  $spk{$kv_id} = 1;
}
die "Chyba: v sondì není definován žádný mluvèí\n" unless ($sp_num > 0);

$_ = <STDIN>;
$line_num++;
die "Chyba: pøepis není .trs soubor v kódování CP1250 pro Windows\n" unless (/^\<\?xml version\=\"1\.0\" encoding\=\"CP1250\"\?\>\r$/);
# s/CP1250/windows-1250/;
print STDOUT $_;

$_ = <STDIN>;
$line_num++;
die "Chyba: pøepis zøejmì nebyl vytvoøen programem Transcriber\n" unless (/^\<\!DOCTYPE Trans SYSTEM \"trans-14\.dtd\"\>\r$/);
print STDOUT $_;

$_ = <STDIN>;
$line_num++;
die "Chyba: pøepis zøejmì nebyl vytvoøen programem Transcriber\n" unless (/^\<Trans[^<>]*\>\r$/);
s/(audio_filename\=\")[^"]*(\")/$1$fileID$2/;
print STDOUT $_;

$_ = <STDIN>;
$line_num++;
die "Chyba: v pøepisu chybí definice mluvèích\n" unless (/^\<Speakers\>\r$/);
print STDOUT $_;

while ((($_ = <STDIN>) =~ /^\<Speaker [^<>]*\>\r$/))
{ # cteni definic mluvcich v prepisu
  $line_num++;
  my $id; my $name;
  if (/id\=\"([^\"]+)\"/)
  {
    $id = $1;
  }
  else
  {
    $id = "";
  }
  if (/name\=\"([^\"]+)\"/)
  {
    $name = $1;
  }
  else
  {
    $name ="";
  }
  die "Chyba: ID mluvèího $id neodpovídá konvencím\n" unless ($id =~ /^spk[1-9]?[0-9]$/);
#  die "Chyba: jméno mluvèího $name neodpovídá pøepisovacím pravidlùm\n" unless ($name =~ /^[1-9]?[0-9]$/);
#  $name = "0".$name if (length($name)==1);
  $idname{$id} = $name;
  mydie "Chyba: mluvèí $name není v databázi definován\n" unless ($spk{$name});
  $spk{$name} = 2;
  print STDOUT $_;
}
$line_num++;
die "Chyba: v pøepisu byl nalezen nadbyteèný element (line: $line_num)\n" unless (/^\<\/Speakers\>\r$/);
print STDOUT $_;

foreach my $f (keys %spk)
{
  if ($spk{$f} != 2)
  {
    $spk{$f} = 2;
    mydie "Chyba: mluvèí $f není definován v pøepisu\n";
  }
}

$_ = <STDIN>;
$line_num++;
die "Chyba: v pøepisu byl nalezen nadbyteèný element (line: $line_num)\n" unless (/^\<Episode[^<>]*\>\r$/);
print STDOUT $_;

$_ = <STDIN>;
$line_num++;
die "Chyba: v pøepisu byl nalezen nadbyteèný element (line: $line_num)\n" unless (/^\<Section [^<>]*\>\r$/);
print STDOUT $_;

##### zacatek cteni vlastniho prepisu #####

while ((($_ = <STDIN>) =~ /^\<Turn [^<>]*\>\r$/))
{
  $line_num++;
  die "Chyba: floating boundary není pøi segmentaci povoleno\n" if (/ime\=\" /);
  my $sync_count = 0;
  my $last_pos = "";   # predchozi pozice v ramci obratu (NE segmentu)
  my $last_pos_1 = ""; # posledni pozice odpovidajiciho predchoziho segmentu...
  my $last_pos_2 = ""; # ...pro pripad prekryvajici se reci: pro mluvciho 1 a 2
  if (/speaker\=\"(spk[0-9]+)\"/)
  {
    $cur_sp = $idname{$1};
    $spk{$cur_sp}++;
    if ($cur_sp eq $last_sp)
    {
      $last_sp .= "E"; # nastaveni priznaku chyby
    }
    else
    {
      $last_sp = $cur_sp;
    }
  }
  elsif (/speaker\=\"(spk[0-9]+) (spk[0-9]+)\"/)
  { # prekryv
    $spk{$idname{$1}}++;
    $spk{$idname{$2}}++;
    $last_sp = "|1";
    $last_sp .= "E" if ($1 eq $2); # nastaveni priznaku chyby
  }
  elsif (!/speaker/i)
  { # nedefinovany mluvci
    $last_sp = "_" unless ($last_sp =~ /_/);
  }
  else
  {
    die "Chyba: v pøepisu byl nalezen nadbyteèný element (line: $line_num)\n";
  }
  print STDOUT $_;

  while ((($_ = <STDIN>) =~ /^\<Sync [^<>]*\>\r$/))
  {
    $line_num++;
    $sync_count++;
    die "Chyba: floating boundary není pøi segmentaci povoleno (line: $line_num)\n" unless (/^\<Sync time\=\"[0-9]+\.?[0-9]*\"\/\>\r$/);
    print STDOUT $_;

PREKRYV:
    $_ = <STDIN>;
    $line_num++;
    if ($last_sp =~ /\|/)
    { # prekryv
      if (/^\<Who nb\=\"([12])\"\/\>\r$/)
      {
        die "Chyba: v pøepisu byl nalezen pøekryv ménì ne¾ dvou mluvèích (line: $line_num)\n" unless ((substr($last_sp,0,1) eq "|") && (substr($last_sp,1,1)) eq $1);
        $last_sp = "|".(substr($last_sp,1,1) + 1).substr($last_sp,2);
        print STDOUT $_;
        $_ = <STDIN>;
        $line_num++;
      }
      else
      {
        die "Chyba: v pøepisu byl nalezen nadbyteèný element nebo prázdný segment (line: $line_num)\n";
      }
    }
    if (!/[<>]/ && /\r$/)
    { # vlastni radek s prepisem
      s/[\t ]+/ /g;
      s/^ //;
      s/ \r/\r/;
      mydie "Chyba: v pøepisu byl nalezen prázdný segment za segmentem zaèínajícím:\n".substr($temp,0,50)."\n" if (/^\r$/);
      if ($last_sp =~ /E/)
      { # priznak odlozene chyby ...
        chop $last_sp; # ... se hned smaze
        if ($last_sp =~ /\|/)
        {
          mydie "Chyba: dva stejní mluvèí se opakují v pøekryvu zaèínajícím:\n".substr($_,0,50)."\n";
        }
        else
        {
          mydie "Chyba: mluvèí $last_sp se opakuje v promluvì zaèínající:\n".substr($_,0,50)." (line: $line_num)\n";
        }
      }
      mydie "Chyba: na segmenty lze dìlit jen promluvy s oznaèením mluvèího:\n".substr($_,0,50)."\n" if (($last_sp =~ /^[_\-]/) && ($sync_count > 1));
      mydie "Chyba: v pøepisech není povolena èárka\n" if (/\,/);
      mydie "Chyba: v pøepisech není povolena dvojteèka\n" if (/[^.]\:/ || (/^\:/));
      mydie "Chyba: v pøepisech nejsou povoleny uvozovky\n" if (/\"/);
      mydie "Chyba: v pøepisech není povolen apostrof\n" if (/\'/);
      mydie "Chyba: v pøepisech není povolen støedník\n" if (/(?<!\&amp)\;/);
      mydie "Chyba: v pøepisech není povolen ampersand\n" if (/\&(?!amp\;)/);
      mydie "Chyba: nalezen nepovolený znak (line: $line_num): \"$1$1\"\n" if (/([\\])/);
      mydie "Chyba: nalezen nepovolený znak (line: $line_num): \"$1\"\n" if (/([\$%+\/=\[\]^_`{}|~\x7f-\x89\x8b\x90-\x99\x9b\xa0-\xa2\xa4\xa6-\xa9\xab-\xae\xb0-\xb2\xb4-\xb8\xbb\xbd\xd7\xdf\xf7\xff])/);
      mydie "Chyba: v pøepisu nalezen øetìzec \"$1\"\n" if (/(\( *(\- *)*\))/);
      if ($last_sp =~ /_/)
      { # neni definovany mluvci
        mydie "Chyba: promluva bez oznaèení mluvèího mùže být jedinì komentáø nebo nerozluštìný usek:\n".substr($_,0,50)."\n" unless (/^\([^()]+\)\r$/ || /^\-\-\-\r$/);
        mydie "Chyba: dva nerozluštìné úseky \"---\" bezprostøednì po sobì\n" if (/^\-/ && ($last_sp eq "_-"));
        mydie "Chyba: dva komentáøe bezprostøednì po sobì:\n".substr($_,0,50)."\n" if (/^\(/ && ($last_sp eq "_("));
        $last_sp = "_".substr($_,0,1);
      }
      else
      { # mluvci je definovan, nastupuje hloubkova kontrola
        $temp = $_; # uschova $_ do $temp kvuli komentarum
        mydie "Chyba: dva komentáøe bezprostøednì po sobì v segmentu zaèínajícím:\n".substr($temp,0,50)."\n" if (/\) ?\(/);
        s/ *\([^()]+\) */ /g; # je treba odfiltrovat komentare z kontrol
	s/^ //;
	s/ \r/\r/;
        mydie "Chyba: špatnì uzávorkovaný komentáø v segmentu zaèínajícím:\n".substr($temp,0,50)."\n" if (/[()]/);
        my $pos_count = 0;
        my $word_count = 0;
        while (/([^ \t\r\n]+)/g)
        {
          my $cur_pos = $1;
          $pos_count++;
          mydie "Chyba: oznaèení \"...:\" smí být jen na konci promluvy v segmentu zaèínajícím:\n".substr($temp,0,50)."\n" if (($last_pos =~ /^\.\.\.\:$/) || (($cur_pos =~ /^\.\.\.\:$/) && ($pos_count == 1)));
          mydie "Chyba: oznaèení \"...\" smí být jen na zaèátku nebo na konci promluvy v segmentu zaèínajícím:\n".substr($temp,0,50)." (line: $line_num) \n" if ((($last_pos =~ /^\.\.\.$/) && (($pos_count != 2) || ($sync_count > 1))) || (($cur_pos =~ /^\.\.\.$/) && ($pos_count == 1) && ($sync_count == 1) && (length($_) <= 5)));
          if ($cur_pos =~ /^\.\.?$/)
          {
            mydie "Chyba: promluva nesmí zaèínat pauzou:\n".substr($temp,0,50)."\n" if (($pos_count == 1) && ($sync_count == 1));
            mydie "Chyba: dvì pauzy bezprostøednì po sobì v segmentu zaèínajícím:\n".substr($temp,0,50)."\n" if ($last_pos =~ /^\.\.?$/);
          }
          elsif ($cur_pos =~ /^\-\-\-$/)
          {
            mydie "Chyba: dva nerozluštìné úseky bezprostøednì po sobì v segmentu zaèínajícím:\n".substr($temp,0,50)."\n" if ($last_pos =~ /^\-\-\-$/);
          }
          elsif ($cur_pos =~ /^\.\.\.\:?$/)
          {
            mydie "Chyba: \"$last_pos\" a \"$cur_pos\" bezprostøednì po sobì v segmentu zaèínajícím:\n".substr($temp,0,50)."\n" if ($last_pos =~ /\.\.\./);
          }
          elsif ($cur_pos =~ /^((\&amp\;)|\#|\@)?\*?[a-zA-Z0-9\-\x80-\xff]+\*?$/)
          {
            $word_count++;
            if ($cur_pos =~ /^[#@]/)
            {
              $cur_pos = substr($cur_pos,1);
            }
            elsif ($cur_pos =~ /^\&amp\;/)
            {
              $cur_pos = substr($cur_pos,5);
            }
            mydie "Chyba: dvì hvìzdièky v jednom slovì nejsou povoleny v segmentu zaèínajícím:\n".substr($temp,0,50)."\n" if ($cur_pos =~ /\*.*\*/);
            mydie "Chyba: pomlèka je povolená jen uprostøed slova: \"$cur_pos\" v segmentu zaèínajícím:\n".substr($temp,0,50)."\n" if ((($cur_pos =~ /^\*?\-/) || ($cur_pos =~ /\-\*?$/)) && ($cur_pos !~ /^\-li$/));
            mydie "Chyba: nalezen øetìzec \"$cur_pos\" v segmentu zaèínajícím:\n".substr($temp,0,50)."\n" if ($cur_pos =~ /^\*?((hm)|(hmmm+)|(ee)|(eeee+)|(mm)|(mmmm+)|([jn][oó]([jn][oó])+)|(t[yý]j[oó])|(ž[eé]j[oó]))\*?$/);
            mydie "Chyba: nalezen øetìzec \"$last_pos $cur_pos\" v segmentu zaèínajícím:\n".substr($temp,0,50)."\n" if (($cur_pos =~ /^[sz][mt]e$/) && ($last_pos =~ /^a?by$/));
            
            mydie "Chyba B: nalezena zkratka \"$cur_pos\" v segmentu:\n" if (
   ($cur_pos !~ /^X[NAM]/) and (($cur_pos !~ /^N[JMNOPX]$/) && ($cur_pos =~ /.[A-Z\x8a-\x8f\xa3-\xaf\xbc\xc0-\xde]/) &&    ($cur_pos !~ /^Ma?c[A-Z\x8a-\x8f\xa3-\xaf\xbc\xc0-\xde][^A-Z0-9\-\x8a-\x8f\xa3-\xaf\xbc\xc0-\xde]+$/) && ($cur_pos !~ /^[A-Z\x8a-\x8f\xa3-\xaf\xbc\xc0-\xde][^A-Z0-9\-\x8a-\x8f\xa3-\xaf\xbc\xc0-\xde]*\-[A-Z\x8a-\x8f\xa3-\xaf\xbc\xc0-\xde][^A-Z0-9\-\x8a-\x8f\xa3-\xaf\xbc\xc0-\xde]+$/))  
   );
	    mydie "Chyba: anonymizaèní zkratky musejí být v samostatném segmentu bez pøekryvu v segmentu zaèínajícím:\n".substr($temp,0,50)."\n" if (($cur_pos =~ /N[JMNOPX]/) && ((length($temp) > 4) || ($last_sp =~ /\|/)))
          }
          else
          {
            if ($cur_pos =~ /^[?!]$/)
            {
              # mydie "Chyba: otazník a vykøièník se neoddìlují mezerou v segmentu zaèínajícím:\n".substr($temp,0,50)."\n";
            }
            else
            {
              mydie "Chyba: nalezen øetìzec \"$cur_pos\" v segmentu zaèínajícím:\n".substr($temp,0,50)."\n";
            }
          }
          $last_pos = $cur_pos;
        }
        mydie "Chyba: pøekroèen limit $MAX_WORDS_IN_SEGMENT slov v segmentu zaèínajícím:\n".substr($temp,0,50)."\n" if ($word_count > $MAX_WORDS_IN_SEGMENT);
        $_ = $temp;
      }
    }
    else
    {
       die "Chyba: v pøepisu byl nalezen nadbyteèný element nebo prázdný segment (line: $line_num)\n";
    }
    print STDOUT $_;
    if ($last_sp =~ /\|/)
    { # special assembler-like hack :-)
      if ($last_sp eq "|2")
      { # konec segmentu 1. mluvciho prekryvu
        $last_pos_1 = $last_pos; # uchovano pro pripadne pokracovani 1. mluvciho
        $last_pos = $last_pos_2; # obnovena posledni pozice 2. mluvciho prekryvu
        goto PREKRYV;            # je potreba precist jeste 2. mluvciho
      }
      else
      { # konec segmentu 2. mluvciho prekryvu
        $last_pos_2 = $last_pos; # uchovano pro pripadne pokracovani 2. mluvciho
        $last_pos = $last_pos_1; # obnovena posledni pozice 1. mluvciho prekryvu
        $last_sp = "|1";         # bude se cist novy sync, opet s 1. mluvcim
      }
    }
  }
  $line_num++;
  die "Chyba: v pøepisu byl nalezen nadbyteèný element (line: $line_num)\n" unless (/^\<\/Turn\>\r$/);
  print STDOUT $_;
}
$line_num++;
die "Chyba: v pøepisu byl nalezen nadbyteèný element (line: $line_num)\n" unless (/^\<\/Section\>\r$/);
print STDOUT $_;

$_ = <STDIN>;
$line_num++;
die "Chyba: v pøepisu byl nalezen nadbyteèný element (line: $line_num)\n" unless (/^\<\/Episode\>\r$/);
print STDOUT $_;

$_ = <STDIN>;
$line_num++;
die "Chyba: v pøepisu byl nalezen nadbyteèný element (line: $line_num)\n" unless (/^\<\/Trans\>\r$/);
print STDOUT $_;

die "Chyba: v pøepisu byl nalezen nadbyteèný element (line: $line_num)\n" if (<STDIN>);

foreach my $f (keys %spk)
{
  mydie "Chyba: mluvèí $f není použit v pøepisu\n" unless ($spk{$f} > 2);
}

die "$err_text" if ($err_text ne "");

