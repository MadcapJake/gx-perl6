unit class CompUnit::Repository::GX does CompUnit::Repository::Locally does CompUnit::Repository;

use nqp;

BEGIN CompUnit::RepositoryRegistry::short-id2class('gx') = 'CompUnit::Repository::GX';

my $first-repo = $*REPO.repo-chain()[0];
PROCESS::<$REPO> := CompUnit::Repository::GX.new: :prefix($*CWD.Str) :next-repo($first-repo);

# $*REPO.repo-chain[*-1].next-repo =
#   CompUnit::Repository::GX.new: :prefix($*CWD.Str);



note 'repo added';

has $!cver = nqp::hllize(nqp::atkey(nqp::gethllsym('perl6', '$COMPILER_CONFIG'), 'version'));
has %!loaded;
has $!precomp;
has $!id;

method !matching-package(CompUnit::DependencySpecification $spec) {
  note 'matching package';
  if $spec.from eq 'Perl6' {
    my $lookup = $.prefix.child('gx').child('short').child(nqp::sha1($spec.short-name));
    if $lookup.e {
      my @dists = $lookup.lines».split("\0").grep({
        Version.new(~$_[0] || '0') ~~ $spec.version-matcher and ~$_[1] ~~ $spec.auth-matcher
      }).map(-> ($ver, $auth, $repo, $path) {
        my %meta = from-json($.prefix.child($repo).child('META6.json').slurp);
        %meta<auth> = $auth;
        join($*SPEC.dir-sep, ($repo, $path)) => %meta
      }).grep({
        $_.value<provides>{$spec.short-name}:exists
      });
      for @dists.sort(*.key).reverse.map(*.kv) -> ($full-path, %meta) {
        note $full-path;
        return ($full-path, %meta);
      }
    }
  }
  Nil
}

method !repo-prefix() {
    my $repo-prefix = CompUnit::RepositoryRegistry.name-for-repository(self) // '';
    $repo-prefix ~= '#' if $repo-prefix;
    $repo-prefix
}

method resolve(CompUnit::DependencySpecification $spec) returns CompUnit {
  note 'resolving...';
  my ($path, %meta) = self!matching-package($spec);
  with $path {
    my $file = $.prefix.child($path);
    return CompUnit.new(
      handle       => CompUnit::Handle,
      short-name   => $spec.short-name,
      version      => Version.new: %meta<version>,
      auth         => %meta<auth>,
      repo         => self,
      repo-id      => $path.Str,
      distribution => Distribution.new(|%meta)
    ) if $path;
    return self.next-repo.resolve($spec) if self.next-repo;
  }
  Nil
}

# Resolves a dependency specification to a concrete dependency. If the
# dependency was not already loaded, loads it. Returns a CompUnit
# object that represents the selected dependency. If there is no
# matching dependency, throws X::CompUnit::UnsatisfiedDependency.
method need(
  CompUnit::DependencySpecification $spec,
  CompUnit::PrecompilationRepository $precomp = self.precomp-repo()
) returns CompUnit:D {
  note "needing $spec.short-name()";
  my ($path, %meta) = self!matching-package($spec);
  # note "path: $path";
  if $path {
    my $name = $spec.short-name;
    return %!loaded{$name} if %!loaded{$name}:exists;

    my $*RESOURCES = Distribution::Resources.new(:repo(self), :dist-id($path));

    my $loader = $.prefix.child($path);
    # my $id = %meta<provides>{$spec.short-name}.subst("lib/", "").subst($*SPEC.dir-sep, "__", :g);
    my $id = nqp::sha1($name, ~ $*REPO.id);
    my $source-name = "{$loader.relative($.prefix)} ({$spec.short-name})";
    say "id:\t\t$id\nloader:\t\t$loader\nsource-name:\t$source-name";
    my $handle = $precomp.try-load($id, $loader, :$source-name);
    my $precompiled = defined $handle;
    $handle //= CompUnit::Loader.load-source-file($loader);
    my $compunit = CompUnit.new(
      :$handle,
      :short-name($spec.short-name),
      :version(Version.new: %meta<version>),
      :auth(%meta<auth>),
      :repo(self),
      :repo-id($id),
      :$precompiled,
      :distribution(Distribution.new(|%meta))
    );
    return %!loaded{$compunit.short-name} = $compunit;
  }
  return self.next-repo.need($spec, $precomp) if self.next-repo;
  X::CompUnit::UnsatisfiedDependency.new(:specification($spec)).throw;
}

method id {
  my $name = self.path-spec;
  $name ~= ',' ~ self.next-repo.id if self.next-repo;
  return nqp::sha1($name)
}

method short-id { 'gx' }

# Returns the CompUnit objects describing all of the compilation
# units that have been loaded by this repository in the current
# process.
method loaded() returns Iterable { %!loaded.values }

multi method Str(CompUnit::Repository::GX:D:) {
  $.prefix.child('gx').Str
}
multi method gist(CompUnit::Repository::GX:D:) { self.path-spec }

method path-spec {
  self.short-id ~ '#' ~ self.Str;
}

method precomp-repo() returns CompUnit::PrecompilationRepository {
  role CanPrecomp {
    my $lle;
    my $profile;
    method may-precomp { True }
    method precompile(IO::Path:D $path, CompUnit::PrecompilationId $id, Bool :$force = False, :$source-name) {
      my $compiler-id = $*PERL.compiler.id;
      my $io = self.store.destination($compiler-id, $id);
      my $RMD = $*RAKUDO_MODULE_DEBUG;
      if not $force and $io.e and $io.s {
          $RMD("$path\nalready precompiled into\n$io") if $RMD;
          self.store.unlock;
          return True;
      }

      my $rev-deps = ($io ~ '.rev-deps').IO;
      if $rev-deps.e {
          for $rev-deps.lines {
              $RMD("removing outdated rev-dep $_") if $RMD;
              self.store.delete($compiler-id, $_);
          }
      }

      $lle     //= Rakudo::Internals.LL-EXCEPTION;
      $profile //= Rakudo::Internals.PROFILE;
      my %ENV := %*ENV;
      %ENV<RAKUDO_PRECOMP_WITH> = $*REPO.repo-chain.[1..*].map(*.path-spec).join(',');
      %ENV<RAKUDO_PRECOMP_LOADING> = to-json @*MODULES // [];
      my $current_dist = %ENV<RAKUDO_PRECOMP_DIST>;
      %ENV<RAKUDO_PRECOMP_DIST> = $*RESOURCES ?? $*RESOURCES.Str !! '{}';

      $RMD("Precompiling $path into $io") if $RMD;
      my $perl6 = $*EXECUTABLE.subst('perl6-debug', 'perl6'); # debugger would try to precompile it's UI
      # my $include = $path.Str.subst($id.subst("__", "/"), "").IO;
      # say $include;
      my $proc = run(
        $perl6,
        $lle,
        $profile,
        "--target=" ~ Rakudo::Internals.PRECOMP-TARGET,
        "--output=$io",
        "--source-name=$source-name",
        '-MCompUnit::Repository::GX',
        $path,
        :out,
        :err,
      );
      %ENV.DELETE-KEY(<RAKUDO_PRECOMP_WITH>);
      %ENV.DELETE-KEY(<RAKUDO_PRECOMP_LOADING>);
      %ENV<RAKUDO_PRECOMP_DIST> = $current_dist;

      my @result = $proc.out.lines.unique;
      if not $proc.out.close or $proc.status {  # something wrong
          self.store.unlock;
          $RMD("Precomping $path failed: $proc.status()") if $RMD;
          Rakudo::Internals.VERBATIM-EXCEPTION(1);
          die $proc.err.slurp-rest.indent(4);
      }

      if $proc.err.slurp-rest -> $warnings {
          $*ERR.print($warnings);
      }
      $RMD("Precompiled $path into $io") if $RMD;
      my str $dependencies = '';
      for @result -> $dependency {
          unless $dependency ~~ /^<[A..Z0..9]> ** 40 \s .+/ {
              say $dependency;
              next
          }
          Rakudo::Internals.KEY_SPACE_VALUE(
            $dependency,my $dependency-id,my $dependency-src);
          my $path = self.store.path($compiler-id, $dependency-id);
          if $path.e {
              $dependencies ~= "$dependency\n";
              spurt($path ~ '.rev-deps', "$id\n", :append);
          }
      }
      spurt($io ~ '.deps', $dependencies);
      self.store.unlock;
      True
    }
  }
  $!precomp := CompUnit::PrecompilationRepository::Default.new(
      store => CompUnit::PrecompilationStore::File.new(
        :prefix($.prefix.child('gx').child('precomp')),
      )
  ) but CanPrecomp unless $!precomp;
  $!precomp
}
