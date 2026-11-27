# Fits the enemy stat curves in curves.lua from a DT_UnitParameter dump (tools/dump_units.lua):
#   perl tools/curves.pl dev_eval_out.txt
use strict; use warnings;
my @F=qw(ID Category Level IsBoss MaxHitPoint MaxBreakPoint Attack Defence Intelligence Mind Agility Divine Experience Money);
my @STATS=qw(MaxHitPoint MaxBreakPoint Attack Defence Intelligence Mind Agility Experience Money);
my %rows;
open my $fh,'<:encoding(UTF-8)',$ARGV[0] or die;
while(<$fh>){chomp; my @c=split /\t/; next if @c<14 || $c[0]!~/^\d+$/; my %r; @r{@F}=@c[0..13];
  next unless $r{Category}==2 || $r{Category}==3; next if $r{Level}<1 || $r{MaxHitPoint}<=0;
  my $k = ($r{Category}==3 || $r{IsBoss} eq 'true') ? 'boss' : 'normal'; push @{$rows{$k}}, \%r;}
sub solve { my ($A,$b)=@_; my $n=@$b; for my $i(0..$n-1){ my $p=$i; for my $r($i+1..$n-1){$p=$r if abs($A->[$r][$i])>abs($A->[$p][$i])} @$A[$i,$p]=@$A[$p,$i]; @$b[$i,$p]=@$b[$p,$i];
  for my $r($i+1..$n-1){ my $f=$A->[$r][$i]/$A->[$i][$i]; $A->[$r][$_]-=$f*$A->[$i][$_] for $i..$n-1; $b->[$r]-=$f*$b->[$i]; } }
  my @x; for(my $i=$n-1;$i>=0;$i--){ my $s=$b->[$i]; $s-=$A->[$i][$_]*$x[$_] for $i+1..$n-1; $x[$i]=$s/$A->[$i][$i]; } return @x; }
for my $k (qw(normal boss)) {
  my $maxL = 0; $_->{Level} > $maxL and $maxL = $_->{Level} for @{$rows{$k}};
  my @knots = grep { $_ < $maxL - 5 } map { $_*10 } 1..9;
  print "-- $k: ".scalar(@{$rows{$k}})." rows, levels up to $maxL, knots @knots\n";
  print "local ".uc($k)." = {\n";
  for my $s (@STATS) {
    my @pts = map { [$_->{Level}, log($_->{$s})] } grep { $_->{$s} > 0 } @{$rows{$k}};
    my $basis = sub { my $L=shift; [1, $L, map { $L>$_ ? $L-$_ : 0 } @knots] };
    my $m = 2+@knots; my @w = (1) x @pts; my @beta;
    for my $it (1..8) {
      my @A = map { [ (0) x $m ] } 1..$m; my @b = (0) x $m;
      for my $i (0..$#pts) { my $x=$basis->($pts[$i][0]); for my $r(0..$m-1){ $b[$r]+=$w[$i]*$x->[$r]*$pts[$i][1]; $A[$r][$_]+=$w[$i]*$x->[$r]*$x->[$_] for 0..$m-1 } }
      $A[$_][$_] += 1e-6 for 0..$m-1;
      @beta = solve(\@A,\@b);
      my @res = map { my $x=$basis->($pts[$_][0]); my $y=0; $y+=$beta[$_]*$x->[$_] for 0..$m-1; $pts[$_][1]-$y } 0..$#pts;
      my @ab = sort { $a <=> $b } map { abs } @res; my $mad = $ab[int(@ab/2)] || 0.1; my $c = 1.5*$mad/0.6745;
      @w = map { my $r=abs($_); $r<=$c ? 1 : $c/$r } @res;
    }
    my @v; my $prev; my $prevL;
    for my $L (1..99) { my $x=$basis->($L); my $y=0; $y+=$beta[$_]*$x->[$_] for 0..$m-1;
      $y = $prev if defined $prev && $y < $prev; $prev=$y; push @v, sprintf("%.4g", exp($y)); }
    print "    $s = { ".join(", ",@v)." },\n";
  }
  print "}\n";
}
