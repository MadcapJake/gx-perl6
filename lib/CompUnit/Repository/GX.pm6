unit class CompUnit::Repository::GX does CompUnit::Repository::Locally does CompUnit::Repository;

use nqp;

# BEGIN CompUnit::RepositoryRegistry::short-id2class('gx') = 'CompUnit::Repository::GX';

# $*REPO.repo-chain[*-1].next-repo =
#   CompUnit::Repository::GX.new: :prefix($*CWD.Str);

my $first-repo = $*REPO.repo-chain()[0];
PROCESS::<$REPO> := CompUnit::Repository::GX.new: :prefix($*CWD.Str) :next-repo($first-repo);

note 'repo added';

has $!cver = nqp::hllize(nqp::atkey(nqp::gethllsym('perl6', '$COMPILER_CONFIG'), 'version'));
has %!loaded;
has $!precomp;
has $!id;

method !matching-package(CompUnit::DependencySpecification $spec) {
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
        return ($full-path, %meta);
      }
    }
  }
  Nil
}

method !repo-prefix() {
    my $repo-prefix = 'gx+ipfs'; # CompUnit::RepositoryRegistry.name-for-repository(self) // '';
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
      version      => %meta<version>,
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
  if $path {
    my $name = $spec.short-name;
    return %!loaded{$name} if %!loaded{$name}:exists;

    my $*RESOURCES = Distribution::Resources.new(:repo(self), :dist-id($path));

    my $loader = IO::Path.new($path);
    my $id = $loader.basename;
    my $source-name = "{$loader.relative($.prefix)} ({$spec.short-name})";
    say "id:\t$id\nloader:\t$loader\nsource-name:\t$source-name";
    my $handle = $precomp.try-load($id, $loader, :$source-name);
    my $precompiled = defined $handle;
    $handle //= CompUnit::Loader.load-source-file($loader);
    my $compunit = CompUnit.new(
      :$handle,
      :short-name($spec.short-name),
      :version(%meta<version>),
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

method short-id { 'gx' }

# Returns the CompUnit objects describing all of the compilation
# units that have been loaded by this repository in the current
# process.
method loaded() returns Iterable { %!loaded.values }

# multi method Str(CompUnit::Repository::GX:D:) { 'CompUnit::Repository::GX' }
# multi method gist(CompUnit::Repository::GX:D:) { self.path-spec }

method path-spec { 'gx#'}

method precomp-repo() returns CompUnit::PrecompilationRepository {
  note 'getting or making precomp';
  $!precomp := CompUnit::PrecompilationRepository::Default.new(
      store => CompUnit::PrecompilationStore::File.new(
        :prefix($.prefix.child('gx').child('precomp')),
      )
  ) unless $!precomp;
  $!precomp
}
