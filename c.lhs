= C Below =

A C implementation of the ION machine is listed below.

It uses a stop-the-world copying garbage collector. It turns out we should
reduce projection functions (such as `fst` and `snd`) as we collect garbage.
See:

  * https://www.cs.ox.ac.uk/publications/publication3788-abstract.html[John
Hughes 1983, 'The design and implementation of programming languages']
  * https://homepages.inf.ed.ac.uk/wadler/papers/leak/leak.ps.gz[Philip Wadler 1987, 'Fixing some space leaks with a garbage collector']

We partially achieve this by reducing `K I T` nodes during garbage collection.

Eliminating applications of `I` during garbage collection makes up for not
doing so during evaluation.

Our simple design means the only garbage collection root we need is the top of
the stack.

== Unfinished business ==

The world of Compiler Quest is rich and open-ended. My in-game Journal brims
with objectives:

  * Fill in missing type checks.
  * Improve parsing and error messages.
  * Optimize the generated code, e.g. specialized code for case expressions.
  * Optimize the compiler, e.g. replace association lists.
  * Experiment with bulk combinators.
  * Look into http://www.cs.cornell.edu/~ross/publications/eqsat/[equality
saturation]: automating compiler optimization.
  * Simulate an ION machine in WebAssembly, allowing for a client-side web
  Haskell REPL.
  * Improve on Haskell, e.g. see suggestions by
  https://medium.com/daml-driven/four-tweaks-to-improve-haskell-b1de9c87f816[Neil Mitchell]
  and
  https://gist.github.com/taktoa/a59400fd3e1c400835b60c416ad33952[Remy Goldschmidt].
  * Program synthesis:
    - link:atp.html[Automatic theorem proving]: generate programs from their types.
    - How does http://nautilus.cs.miyazaki-u.ac.jp/~skata/MagicHaskeller.html[MagicHaskeller] work?! It generates programs from test cases.
    - link:differ.html[Differentiable programming]: generate approximately correct programs from test cases.

[source,c]
------------------------------------------------------------------------
typedef unsigned u;
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

enum { FORWARD = 27, REDUCING = 9 };

void die(char *s) { fprintf(stderr, "error: %s\n", s); exit(1); }

enum { TOP = 1<<23, TABMAX = 1<<10, BUFMAX = 1<<20 };
u arena[2][TOP];
u *mem, *altmem, *sp, *spTop, hp, tab[TABMAX], tabn;

void stats() { printf("[HP = %u, stack usage = %ld]\n", hp, spTop - sp); }

static inline u isAddr(u n) { return n>=128; }

u copy(u n) {
  if (!isAddr(n)) return n;
  u x = mem[n];
  while (isAddr(x) && mem[x] == 'T') {
    mem[n] = mem[n + 1];
    mem[n + 1] = mem[x + 1];
    x = mem[n];
  }
  if (isAddr(x) && mem[x] == 'K') {
    mem[n + 1] = mem[x + 1];
    x = mem[n] = 'I';
  }
  u y = mem[n + 1];
  switch(x) {
    case FORWARD: return y;
    case REDUCING:
      if (hp >= TOP - 2) die("OOM");
      mem[n] = FORWARD;
      mem[n + 1] = hp;
      hp += 2;
      return mem[n + 1];
    case 'I':
      mem[n] = REDUCING;
      y = copy(y);
      if (mem[n] == FORWARD) {
        altmem[mem[n + 1]] = 'I';
        altmem[mem[n + 1] + 1] = y;
      } else {
        mem[n] = FORWARD;
        mem[n + 1] = y;
      }
      return mem[n + 1];
    default: break;
  }
  if (hp >= TOP - 2) die("OOM");
  u z = hp;
  hp += 2;
  mem[n] = FORWARD;
  mem[n + 1] = z;
  altmem[z] = copy(x);
  altmem[z + 1] = x == 'a' || x == '#' ? y : copy(y);
  return z;
}

void gc() {
  hp = 128;
  sp = altmem + TOP - 1;
  *sp = copy(*spTop);
  spTop = sp;
  u *tmp = mem;
  mem = altmem;
  altmem = tmp;
}

u app(u f, u x) {
  mem[hp] = f;
  mem[hp + 1] = x;
  hp += 2;
  return hp - 2;
}

u tab[TABMAX], tabn;

u parseTerm(u (*get)()) {
  u n, c;
  do c = get(); while (c == '\n');
  switch(c) {
    case '`':
      c = parseTerm(get);
      return app(c, parseTerm(get));
    case '#': return app('#', get());
    case '@': return tab[get() - ' '];
    case '(':
      n = 0;
      while ((c = get()) != ')') n = 10*n + c - '0';
      return app('#', n);
    case '[':
      n = 0;
      while ((c = get()) != ']') n = 10*n + c - '0';
      return tab[n];
    default: return c;
  }
}

void reset(u root) { *(sp = spTop) = root; }

void parseMore(u (*get)()) {
  for(;;) {
    u c = parseTerm(get);
    if (!c) {
      reset(app(
            app(app(tab[tabn - 1], app('0', '?')), '.'),
            app('T', '1')));
      return;
    }
    if (tabn == TABMAX) die ("table overflow");
    tab[tabn++] = c;
    if (get() != ';') die("expected ';'");
  }
}

char *str;
u str_get() { return *(unsigned char*)str++; }

void parse(char *s) {
  hp = 128;
  tabn = 0;
  str = s;
  parseMore(str_get);
}

u arg(u n) { return mem[sp [n] + 1]; }
u num(u n) { return mem[arg(n) + 1]; }

void lazy(u height, u f, u x) {
  u *p = mem + sp[height];
  *p = f;
  *++p = x;
  sp += height;
}

u apparg(u i, u j) { return app(arg(i), arg(j)); }

void run(u (*get)(), void (*put)(u)) {
  u c;
  for(;;) {
    // static int ctr; if (++ctr == (1<<25)) stats(), ctr = 0;
    if (mem + hp > sp - 8) gc();
    u x = *sp;
    if (isAddr(x)) *--sp = mem[x]; else switch(x) {
      case FORWARD: stats(); die("stray forwarding pointer");
      case '.': return;
      case 'Y': lazy(1, arg(1), sp[1]); break;
      case 'S': lazy(3, apparg(1, 3), apparg(2, 3)); break;
      case 'B': lazy(3, arg(1), apparg(2, 3)); break;
      case 'C': lazy(3, apparg(1, 3), arg(2)); break;
      case 'R': lazy(3, apparg(2, 3), arg(1)); break;
      case 'I': sp[1] = arg(1); sp++; break;
      case 'T': lazy(2, arg(2), arg(1)); break;
      case 'K': lazy(2, 'I', arg(1)); break;
      case ':': lazy(4, apparg(4, 1), arg(2)); break;
      case '0': c = get(); !c ? lazy(1, 'I', 'K') : lazy(1, app(':', app('#', c)), app('0', '?')); break;
      case '#': lazy(2, arg(2), sp[1]); break;
      case '1': put(num(1)); lazy(2, app(arg(2), '.'), app('T', '1')); break;
      case '=': num(1) == num(2) ? lazy(2, 'I', 'K') : lazy(2, 'K', 'I'); break;
      case 'L': num(1) <= num(2) ? lazy(2, 'I', 'K') : lazy(2, 'K', 'I'); break;
      case '*': lazy(2, '#', num(1) * num(2)); break;
      case '/': lazy(2, '#', num(1) / num(2)); break;
      case '%': lazy(2, '#', num(1) % num(2)); break;
      case '+': lazy(2, '#', num(1) + num(2)); break;
      case '-': lazy(2, '#', num(1) - num(2)); break;
      default: printf("?%u\n", x); die("unknown combinator");
    }
  }
}

char buf[BUFMAX];
char *bufptr, *buf_end;
void buf_reset() { bufptr = buf; }
void buf_put(u c) {
  if (bufptr == buf_end) die("buffer overflow");
  *bufptr++ = c;
}

char *parenthetically =
/*
uncurry x y = y x;
(.) x y z = x (y z);

pair x y f = f x y;
(||) f g x y = f x (g x y);
(++) xs ys = xs ys (\x xt -> x : (xt ++ ys));
ifNull xs a b = xs a (\_ _ -> b);
add r acc p = r (ifNull acc p ('`':(acc ++ p)));
isPre h = h('#'(==)) || h('@'(==));
suffix f h t = isPre h (t undefined (\a b -> pair (a:[]) b)) (pair [] t) (\x y -> f (h:x) y);
atom r h acc t = suffix (add r acc) h t;
sub r acc = uncurry (add r acc) . r "";
closes h = h(';'(==)) || h(')'(==));
if3 h x y z = closes h x (h('('(==)) y z);
switch r a h t = if3 h pair (sub r) (atom r h) a t;
term acc s = s undefined (\h t -> switch term acc h t);
parse s = s "" (\_ _ -> term "" s (\p t -> p ++ (';':parse t)));
*/
"``BCT;"
"``BS`BB;"
"`Y``B`CS``B`B`C``BB:C;"
"``B`R``BKK`BB;"
"``C``BBB``S``BS@#``B`B`:#`@\";"
"``S``B@!`T`##=`T`#@=;"
"``B`S``BC``C``BS``C``BB@%``C`T?``B@ ``C:K`@ K``C``BBB:;"
"``BC``B`B@&@$;"
"``S``BC``B`BB``B`BT@$`TK;"
"``S``B@!`T`#;=`T`#)=;"
"``S``BC``B`BB``B`BB@)`T`#(=;"
"``BC``S``BS``B`C``C@*@ @(@';"
"`Y``B`B`C`T?@+;"
"`Y``B`S`TK``B`BK``B`BK``B`C`@,K``B`C``BB@\"`B`:#;;"
;

char *exponentially =
/*
id x = x;
const x _ = x;
(&) x f = f x;
flip f x y = f y x;
fix x = x (fix x);
Nothing x _ = x;
Just x f g = g x;
P x y f = f x y;
(||) f g x y = f x (g x y);
(++) xs ys = xs ys (\x xt -> x : (xt ++ ys));
pure x inp = Just (P x inp);
bind f m = m Nothing (\x -> x f);
(<*>) x y = \inp -> bind (\a t -> bind (\b u -> pure (a b) u) (y t)) (x inp);
(<$>) f x = pure f <*> x;
(*>) p q = (\_ x -> x) <$> p <*> q;
(<*) p q = (\x _ -> x) <$> p <*> q;
(<|>) x y = \inp -> (x inp) (y inp) Just;
R s   = \a b c d -> a s;
V v   = \a b c d -> b v;
A x y = \a b c d -> c x y;
L x y = \a b c d -> d x y;
sat f inp = inp Nothing (\h t -> f h (pure h t) Nothing);
char c = sat (\x -> x(c(==)));
var = sat (\c -> flip (c(';'(==)) || c(')'(==))));
pre = (:) <$> (char '#' <|> char '@') <*> (flip (:) const <$> sat (const const));
atom r = (char '(' *> (r <* char ')')) <|> (char '\\' *> (L <$> var) <*> (char '.' *> r)) <|> (R <$> pre) <|> (V <$> var);
apps r = (((&) <$> atom r) <*> ((\vs v x -> vs (A x v)) <$> apps r)) <|> pure id;
expr = ((&) <$> atom expr) <*> apps expr;
show t = t id (\v -> v:[])(\x y -> '`':(show x ++ show y)) undefined;
unlam v = fix (\r t -> t (\x -> A (V 'K') (R x)) (\x -> x(v(==)) (V 'I') (A (V 'K') (V x))) (\x y -> A (A (V 'S') (r x)) (r y)) undefined);
babs t = t R V (\x y -> A (babs x) (babs y)) (\x y -> unlam x (babs y));
main s = (expr <* char ';') s "" (\p -> p (\x t -> show (babs x) ++ ";" ++ main t)));
*/
"BKT;"
"BCT;"
"BS(BB);"
"Y(B(CS)(B(B(C(BB:)))C));"
"B(B@ )@!;"
"B(C(TK))T;"
"C(BB(B@%(C(BB(B@%(B@$))))));"
"B@&@$;"
"B@&(@'(KI));"
"B@&(@'K);"
"B(B(R@ ))S;"
"B(BK)(B(BK)(B(BK)T));"
"BK(B(BK)(B(BK)T));"
"B(BK)(B(BK)(B(B(BK))(BCT)));"
"B(BK)(B(BK)(B(BK)(BCT)));"
"B(C(TK))(B(B(RK))(C(BS(BB))@$));"
"B@/(BT(T=));"
"@/(BC(S(B@\"(T(#;=)))(T(#)=))));"
"@&(@':(@*(@0##)(@0#@)))(@'(C:K)(@/(KK)));"
"C(B@*(C(B@*(S(B@*(B(@((@0#())(C@)(@0#)))))(B(@&(@((@0#\\)(@'@.@1)))(@((@0#.)))))(@'@+@2)))(@'@,@1);"
"Y(B(R(@$I))(B(B@*)(B(S(B@&(B(@'T)@3)))(B(@'(C(BBB)(C@-)))))));"
"Y(S(B@&(B(@'T)@3))@4);"
"Y(B(R?)(B(C(C(TI)(C:K)))(B(B(B(:#`)))(S(BC(B(BB)(B@#)))I))));"
"BY(B(B(R?))(C(BB(BC(B(C(T(B(@-(@,#K))@+)))(C(BS(B(R(@,#I))(BT(T=))))(B(@-(@,#K))@,)))))(S(BC(B(BB)(B(B@-)(B(@-(@,#S))))))I)));"
"Y(S(BC(B(C(C(T@+)@,))(S(BC(B(BB)(B@-)))I)))(C(BB@7)));"
"Y(B(C(C(@)@5(@0#;))K))(BT(C(BB(B@#(C(B@#(B@6@8))(:#;K)))))));"
;
char *practically =
// Same as above, except:
/*
occurs v t = t (\x -> (\_ y -> y)) (\x -> x(v(==))) (\x y -> occurs v x || occurs v y) undefined;
unlam v t = occurs v t (t undefined (const (V 'I')) (\x y -> A (A (V 'S') (unlam v x)) (unlam v y)) undefined) (A (V 'K') t);
*/
"BKT;"
"BCT;"
"BS(BB);"
"Y(B(CS)(B(B(C(BB:)))C));"
"B(B@ )@!;"
"B(C(TK))T;"
"C(BB(B@%(C(BB(B@%(B@$))))));"
"B@&@$;"
"B@&(@'(KI));"
"B@&(@'K);"
"B(B(R@ ))S;"
"B(BK)(B(BK)(B(BK)T));"
"BK(B(BK)(B(BK)T));"
"B(BK)(B(BK)(B(B(BK))(BCT)));"
"B(BK)(B(BK)(B(BK)(BCT)));"
"B(C(TK))(B(B(RK))(C(BS(BB))@$));"
"B@/(BT(T=));"
"@/(BC(S(B@\"(T(#;=)))(T(#)=))));"
"@&(@':(@*(@0##)(@0#@)))(@'(C:K)(@/(KK)));"
"C(B@*(C(B@*(S(B@*(B(@((@0#())(C@)(@0#)))))(B(@&(@((@0#\\)(@'@.@1)))(@((@0#.)))))(@'@+@2)))(@'@,@1);"
"Y(B(R(@$I))(B(B@*)(B(S(B@&(B(@'T)@3)))(B(@'(C(BBB)(C@-)))))));"
"Y(S(B@&(B(@'T)@3))@4);"
"Y(B(R?)(B(C(C(TI)(C:K)))(B(B(B(:#`)))(S(BC(B(BB)(B@#)))I))));"
"Y\\a.\\b.\\c.c(\\d.KI)(\\d.d(b=))(\\d.\\e.@\"(abd)(abe))?;"
"Y\\a.\\b.\\c.@7bc(c?(K(@,#I))(\\d.\\e.@-(@-(@,#S)(abd))(abe))?)(@-(@,#K)c);"
"Y(S(BC(B(C(C(T@+)@,))(S(BC(B(BB)(B@-)))I)))(C(BB@8)));"
"Y(B(C(C(@)@5(@0#;))K))(BT(C(BB(B@#(C(B@#(B@6@9))(:#;K)))))));"
;
char *singularity =
"\\a.\\b.\\c.\\d.ac(bcd);"
"Y\\a.\\b.\\c.\\d.\\e.b(cd\\f.\\g.e)\\f.\\g.ce\\h.\\i.f(h=)(agide)e;"
"Y\\a.\\b.\\c.bc\\d.\\e.:d(aec);"
"\\a.\\b.\\c.cab;"
"\\a.\\b.\\c.ca;"
"\\a.\\b.@$(@#ab);"
"\\a.\\b.bK\\c.\\d.ac(@%cd)K;"
"\\a.\\b.bK\\c.ca;"
"\\a.\\b.\\c.@'(\\d.\\e.@'(\\f.\\g.@%(df)g)(be))(ac);"
"\\a.\\b.@((@%a)b;"
"\\a.\\b.\\c.ac(bc)@$;"
"Y\\a.\\b.\\c.\\d.dc\\e.\\f.be(abcf);"
"\\a.\\b.\\c.@((@)ab)c;"
"Y\\a.\\b.@*(@,:b(ab))(@%K);"
"\\a.@,:a(@-a);"
"\\a.@&\\b.b(a=);"
"@,(KI);"
"@,K;"
"@0(@/#-)(@0(@/#-)(@0(@-(@&\\a.C(a(#\n=))))(@/#\n)));"
"@-(@*(@&\\a.@ (a(# =))(a(#\n=)))@2);"
"\\a.@1a@3;"
"B@4@/;"
"\\a.\\b.\\c.\\d.Cad(bcd);"
"@4(@.(@&\\a.@6(#z(aL))(a(#aL))));"
"\\a.\\b.\\c.\\d.\\e.ba;"
"\\a.\\b.\\c.\\d.\\e.ca;"
"\\a.\\b.\\c.\\d.\\e.\\f.eab;"
"\\a.\\b.\\c.\\d.\\e.\\f.fab;"
"@)(C:K)(@4(@&(KK)));"
"@*(@0(@/#@)@<)(@,:(@/##)@<);"
"\\a.@0(@5#\\)(@,(C(@+@;))(@.@7)(@0(@/#-)(@0(@5#>)a)));"
"\\a.@*(@*(@*(@0(@5#()(@1a(@5#))))(@>a))(@)@8@=))(@)@9@7);"
"Y\\a.\\b.@*(@,T(@?b)(@)(\\c.\\d.\\e.c(@:ed))(ab)))(@%I);"
"Y\\a.@,T(@?a)(@@a);"
"@,@#@7(@,(C(@+@;))(@-@7)(@0(@5#=)@A));"
"@0@3(@.(@1@B(@5#;)));"
"\\a.\\b.@+(\\c.\\d.@!a(cK)(\\e.:#@(:eK))(Bd\\e.# (#!-)(e+)))(Ka)b# ;"
"Y\\a.\\b.\\c.cI(\\d.@Ddb)(\\d.\\e.:#`(@\"(abd)(abe)))?;"
"Y\\a.\\b.\\c.c(\\d.KI)(\\d.@!bd)(\\d.\\e.@ (abd)(abe))\\d.\\e.C(@ (@!bd)(C(abe)));"
"Y\\a.\\b.\\c.@Fbc(c?(K(@8(:#IK)))(\\d.\\e.@:(@:(@9(:#SK))(abd))(abe))?)(@:(@9(:#KK))c);"
"Y\\a.\\b.b@8@9(\\c.\\d.@:(ac)(ad))\\c.\\d.@Gc(ad);"
"Y\\a.\\b.\\c.cK\\d.\\e.@\"(@Eb(@H(d(KI))))(:#;(abe));"
"\\a.@Ca(:#?K)(B(\\b.@Ibb)(TK));"
;

FILE *fp;
void fp_reset(char *f) { fp = fopen(f, "r"); }
u fp_get() {
  u c = fgetc(fp);
  return c == EOF ? fclose(fp), 0 : c;
}

void pc(u c) { putchar(c); fflush(stdout); }

void lvlup(char *prog) {
  parse(buf);
  str = prog;
  buf_reset();
  run(str_get, buf_put);
  *bufptr = 0;
}

void lvlup_file(char *filename) {
  printf("loading %s...\n", filename);
  parse(buf);
  fp_reset(filename);
  buf_reset();
  run(fp_get, buf_put);
  *bufptr = 0;
}

int main(int argc, char **argv) {
  mem = arena[0]; altmem = arena[1];
  buf_end = buf + BUFMAX;
  spTop = mem + TOP - 1;
  bufptr = buf + 2;

  strcpy(buf, "I;");
  lvlup(parenthetically);
  lvlup(exponentially);
  lvlup(practically);
  lvlup(singularity);
  lvlup_file("singularity");
  lvlup_file("semantically");
  lvlup_file("stringy");
  lvlup_file("binary");
  lvlup_file("algebraically");
  lvlup_file("parity.hs");
  lvlup_file("fixity.hs");
  lvlup_file("typically.hs");
  lvlup_file("classy.hs");
  lvlup_file("classy.hs");

  parse(buf); fp_reset("classy.hs"); run(fp_get, pc);
  return 0;
}
------------------------------------------------------------------------
