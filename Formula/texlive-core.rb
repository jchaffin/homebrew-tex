# This formula installs core components of TeX Live that can be used by multiple
# formulae.
#
# Requirements of this formula and motivation for design choices:
#
# * No dependencies
#   - Reduce the dependencies of dependent formulae
# * All binaries and scripts work without any other TeX tools installed
#   - Make it easy to test the installed components
# * Patching should be minimal but enough for scripts and dependent formulae
#   - Reduce the necessary changes between updates

class TexliveCore < Formula
  desc "TeX Live core including kpathsea, scripts, configuration"
  homepage "https://www.tug.org/texlive/"
  url "https://github.com/texbrew/texlive-core/archive/2018.01pre.tar.gz"
  sha256 "709676adb4cd33ca28c656f6d6d56ebb9f6858f58ce9349d47409a3251b668c9"

  # texmf.cnf contains search paths and directories used by kpathsea. We patch
  # these to fit the TeXbrew directory structure.
  patch :DATA

  def install
    ## Install files that don't require building.

    (pkgshare/"texbrew").install Dir["texmf-dist/*"]
    pkgshare.install "tlpkg"
    info.install Dir["info/*"]

    ## Install files from the source.

    chdir "texk/kpathsea" do
      # Configure. See <texlive-source>/texk/kpathsea/ac/*.ac for defaults.
      system "./configure",
        "--disable-dependency-tracking",  # Speed up configure
        "--disable-silent-rules",         # Speed up configure
        "--disable-static",               # No statically linked executables
        "--enable-shared",                # Use shared libraries
        # Disable programs that create missing files when they are not found.
        # Until proven otherwise, we assume that these are called due to bugs
        # rather than an actual need to create files.
        # See https://tug.org/texinfohtml/kpathsea.html#mktex-configuration
        "--without-mktexfmt-default",
        "--without-mktexmf-default",
        "--without-mktexocp-default",
        "--without-mktexofm-default",
        "--without-mktexpk-default",
        "--without-mktextex-default",
        "--without-mktextfm-default",
        #############################
        "--prefix=#{prefix}"              # Install prefix

      # Build and install.
      system "make", "install"
    end

    chdir "texk/texlive" do
      # Configure.
      system "./configure",
        "--disable-dependency-tracking",  # Speed up configure
        "--disable-silent-rules",         # Speed up configure
        "--disable-linked-scripts",       # Ignore linked_scripts. See below.
        "--prefix=#{prefix}"              # Install prefix

      # Install tl_scripts.
      chdir "tl_scripts" do
        system "make", "install"
      end

      # Install fmtutil and updmap from linked_scripts.
      { "fmtutil.pl"      => "fmtutil",
        "fmtutil-sys.sh"  => "fmtutil-sys",
        "fmtutil-user.sh" => "fmtutil-user",
        "updmap.pl"       => "updmap",
        "updmap-sys.sh"   => "updmap-sys",
        "updmap-user.sh"  => "updmap-user"
      }.each do |name, link|
        scripts = pkgshare/"texbrew/scripts/texlive"
        scripts.install "linked_scripts/texlive/#{name}"
        bin.install_symlink scripts/name => link
      end

    end

    ## Remove non-core files.

    # Requires dvips.
    rm_rf Dir[prefix/"**/all*"]
    rm_rf Dir[prefix/"**/dvired*"]
    rm_rf Dir[prefix/"**/dvi2fax*"]

    # Requires epstopdf. Broken according to man page.
    rm_rf Dir[prefix/"**/e2pall*"]

    # Requires tex.
    rm_rf Dir[prefix/"**/fontinst*"]

    # Obsolete according to man page.
    rm_rf Dir[prefix/"**/ps2frag*"]

    # Requires latex.
    rm_rf Dir[prefix/"**/pslatex*"]

    # Requires bibtex.
    rm_rf Dir[prefix/"**/rubibtex*"]

    # Requires makeindex.
    rm_rf Dir[prefix/"**/rumakeindex*"]

    # Create the filename database file (ls-R) for this formula.
    system bin/"mktexlsr", prefix
  end

  test do
    # kpsewhich: Find the main configuration file. This is a minimum for every
    # binary built with kpathsea.
    system bin/"kpsewhich", "texmf.cnf"

    # kpsewhich: Find a file with the format 'web2c files'.
    system bin/"kpsewhich", "--format=web2c files", "mktexdir.opt"

    # kpseaccess: Check if the file is readable.
    system bin/"kpseaccess", "r", info/"tds.info"

    # kpsestate: Check if the file has the given mode.
    assert_equal "644", shell_output("#{bin}/kpsestat = #{info}/tds.info").strip
  end
end


## The following documentation describes the patches below.


# -----------------------
# texk/kpathsea/texmf.cnf
# -----------------------
#
# TEXMFROOT is the root directory for a TeXLive distribution (assuming TDS).
# TEXMFROOT includes the distribution directory TEXMFDIST (which is correct in
# texmf.cnf) and the directory for local additions TEXMFLOCAL (which is left for
# users and explicitly not used by TeXbrew).
#
# TEXMFROOT is so-named because it is the root of a portable TeX Live
# distribution. However, we use a directory hierarchy specifically for TeXbrew,
# which is not portable.
#
# TEXMFDIST is for distribution (not user) configuration files. It is use by
# TeXbrew formulae and should not be changed by users. Since we use separate
# directories for formulae, the default value of __one__ directory
# ($TEXMFROOT/texmf-dist) does not work (unless we want to work outside the
# normal bounds of Homebrew). Instead, we use the kpathsea subdirectory
# expansion (with the double slash syntax //) to represent the approximate set
# of directories of this file glob:
#
#   $HOMEBREW_PREFIX/share/*/texmf-dist
#
# TEXMFLOCAL is reserved for users. Configuration files in this directory
# override configuration files in TEXMFDIST.
#
# TEXMFSYSVAR is where {fmtutil,updmap}-sys store cached runtime data.
#
# TEXMFSYSCONFIG is where {fmtutil,updmap}-sys store configuration data.
#
# TEXMF is the list of all texmf directory trees. Due to the aforementioned
# change in TEXMFDIST, the !! in front of $TEXMFDIST (meaning search only the
# ls-R filename database) does not work.
#
# TEXMFCNF is the compile-time list of search paths for texmf.cnf. Rather than
# use all of the paths defined for a TeXLive distribution, we provide 3 paths:
#
#   1. HOMEBREW_PREFIX/share/texbrew-local/web2c - user overriding
#   2. $SELFAUTODIR (parent directory of executable) - formula overriding
#   3. HOMEBREW_PREFIX/share/texlive-core/texbrew/web2c - this formula


# ----------------------------------------------
# texk/{kpathsea,texlive/tl_scripts}/Makefile.in
# ----------------------------------------------
#
# Replace the 'texmf-dist' directory in several places to suit our directory
# structure.


# -------------------------------------------------------
# texk/texlive/linked_scripts/texlive/{fmtutil,updmap}.pl
# -------------------------------------------------------
#
# Replace the Perl include path ('@INC') addition to suit our directory
# strucure.


__END__
diff --git a/texk/kpathsea/texmf.cnf b/texk/kpathsea/texmf.cnf
--- a/texk/kpathsea/texmf.cnf
+++ b/texk/kpathsea/texmf.cnf
@@ -58,23 +58,23 @@
 % SELFAUTOPARENT (its grandparent = /usr/local/texlive/YYYY), and
 % SELFAUTOGRANDPARENT (its great-grandparent = /usr/local/texlive).
 % Sorry for the off-by-one-generation names.
-TEXMFROOT = $SELFAUTOPARENT
+TEXMFROOT = HOMEBREW_PREFIX/share

 % The main tree of distributed packages and programs:
-TEXMFDIST = $TEXMFROOT/texmf-dist
+TEXMFDIST = $TEXMFROOT//texbrew

 % We used to have a separate /texmf tree with some core programs and files.
 % Keep the variable name.
 TEXMFMAIN = $TEXMFDIST

 % Local additions to the distribution trees.
-TEXMFLOCAL = $SELFAUTOGRANDPARENT/texmf-local
+TEXMFLOCAL = HOMEBREW_PREFIX/share/texbrew-local

 % TEXMFSYSVAR, where *-sys store cached runtime data.
-TEXMFSYSVAR = $TEXMFROOT/texmf-var
+TEXMFSYSVAR = HOMEBREW_PREFIX/var/texbrew

 % TEXMFSYSCONFIG, where *-sys store configuration data.
-TEXMFSYSCONFIG = $TEXMFROOT/texmf-config
+TEXMFSYSCONFIG = HOMEBREW_PREFIX/etc/texbrew

 % Per-user texmf tree(s) -- organized per the TDS, as usual.  To define
 % more than one per-user tree, set this to a list of directories in
@@ -107,7 +107,7 @@ TEXMFAUXTREES = {}
 % The odd-looking $TEXMFAUXTREES$TEXMF... construct is so that if no auxtree is
 % ever defined (the 99% common case), no extra elements will be added to
 % the search paths. tlmgr takes care to end any value with a trailing comma.
-TEXMF = {$TEXMFAUXTREES$TEXMFCONFIG,$TEXMFVAR,$TEXMFHOME,!!$TEXMFLOCAL,!!$TEXMFSYSCONFIG,!!$TEXMFSYSVAR,!!$TEXMFDIST}
+TEXMF = {$TEXMFAUXTREES$TEXMFCONFIG,$TEXMFVAR,$TEXMFHOME,!!$TEXMFLOCAL,!!$TEXMFSYSCONFIG,!!$TEXMFSYSVAR,$TEXMFDIST}

 % Where to look for ls-R files.  There need not be an ls-R in the
 % directories in this path, but if there is one, Kpathsea will use it.
@@ -511,33 +511,7 @@ RUBYINPUTS   = .;$TEXMF/scripts/{$progname,$engine,}/ruby//
 % since we don't want to scatter ../'s throughout the value.  Hence we
 % explicitly list every directory.  Arguably more understandable anyway.
 %
-TEXMFCNF = {\
-$SELFAUTOLOC,\
-$SELFAUTOLOC/share/texmf-local/web2c,\
-$SELFAUTOLOC/share/texmf-dist/web2c,\
-$SELFAUTOLOC/share/texmf/web2c,\
-$SELFAUTOLOC/texmf-local/web2c,\
-$SELFAUTOLOC/texmf-dist/web2c,\
-$SELFAUTOLOC/texmf/web2c,\
-\
-$SELFAUTODIR,\
-$SELFAUTODIR/share/texmf-local/web2c,\
-$SELFAUTODIR/share/texmf-dist/web2c,\
-$SELFAUTODIR/share/texmf/web2c,\
-$SELFAUTODIR/texmf-local/web2c,\
-$SELFAUTODIR/texmf-dist/web2c,\
-$SELFAUTODIR/texmf/web2c,\
-\
-$SELFAUTOGRANDPARENT/texmf-local/web2c,\
-$SELFAUTOPARENT,\
-\
-$SELFAUTOPARENT/share/texmf-local/web2c,\
-$SELFAUTOPARENT/share/texmf-dist/web2c,\
-$SELFAUTOPARENT/share/texmf/web2c,\
-$SELFAUTOPARENT/texmf-local/web2c,\
-$SELFAUTOPARENT/texmf-dist/web2c,\
-$SELFAUTOPARENT/texmf/web2c\
-}
+TEXMFCNF = HOMEBREW_PREFIX/share/texbrew-local/web2c;$SELFAUTODIR;HOMEBREW_PREFIX/share/texlive-core/texbrew/web2c
 %
 % For reference, here is the old brace-using definition:
 %TEXMFCNF = {$SELFAUTOLOC,$SELFAUTODIR,$SELFAUTOPARENT}{,{/share,}/texmf{-local,}/web2c}
diff --git a/texk/kpathsea/Makefile.in b/texk/kpathsea/Makefile.in
--- a/texk/kpathsea/Makefile.in
+++ b/texk/kpathsea/Makefile.in
@@ -794,7 +794,7 @@ progname_test_CPPFLAGS = $(AM_CPPFLAGS) -DMAKE_KPSE_DLL -DTEST
 progname_test_SOURCES = progname.c
 progname_test_LDADD = libkpathsea.la
 xdirtest_LDADD = libkpathsea.la
-web2cdir = $(datarootdir)/texmf-dist/web2c
+web2cdir = $(datarootdir)/texlive-core/texbrew/web2c
 dist_web2c_SCRIPTS = mktexdir mktexnam mktexupd
 dist_web2c_DATA = mktex.opt mktexdir.opt mktexnam.opt
 dist_noinst_SCRIPTS = mktexlsr mktexmf mktexpk mktextfm
diff --git a/texk/texlive/tl_scripts/Makefile.in b/texk/texlive/tl_scripts/Makefile.in
--- a/texk/texlive/tl_scripts/Makefile.in
+++ b/texk/texlive/tl_scripts/Makefile.in
@@ -275,7 +275,7 @@ sh_scripts = \
 	texlinks

 nodist_bin_SCRIPTS = $(am__append_1)
-scriptsdir = texmf-dist/scripts/texlive
+scriptsdir = texlive-core/texbrew/scripts/texlive
 all_scripts = $(lua_scripts) $(perl_scripts) $(shell_scripts)
 @WIN32_TRUE@@WIN32_WRAP_TRUE@wrappers = $(all_scripts:=.exe)
 @WIN32_TRUE@@WIN32_WRAP_TRUE@runscript = $(top_srcdir)/../../texk/texlive/$(WIN_WRAPPER)/runscript.exe
@@ -318,13 +318,13 @@ man1_links = \
 	texconfig:texconfig-sys \
 	updmap:updmap-sys

-texconfigdir = $(datarootdir)/texmf-dist/texconfig
+texconfigdir = $(datarootdir)/texlive-core/texbrew/texconfig
 dist_texconfig_SCRIPTS = tcfmgr
 dist_texconfig_DATA = tcfmgr.map
-web2cdir = $(datarootdir)/texmf-dist/web2c
+web2cdir = $(datarootdir)/texlive-core/texbrew/web2c
 dist_web2c_DATA = fmtutil.cnf
 Master_dir = $(top_srcdir)/../../../../Master
-tl_scripts_dir = $(Master_dir)/texmf-dist/scripts/texlive
+tl_scripts_dir = $(Master_dir)/texlive-core/texbrew/scripts/texlive
 #
 texlinks_prog = $(DESTDIR)$(bindir)/texlinks
 #
diff --git a/texk/texlive/linked_scripts/texlive/fmtutil.pl b/texk/texlive/linked_scripts/texlive/fmtutil.pl
--- a/texk/texlive/linked_scripts/texlive/fmtutil.pl
+++ b/texk/texlive/linked_scripts/texlive/fmtutil.pl
@@ -19,7 +19,7 @@ BEGIN {
     die "$0: kpsewhich -var-value=TEXMFROOT failed, aborting early.\n";
   }
   chomp($TEXMFROOT);
-  unshift(@INC, "$TEXMFROOT/tlpkg", "$TEXMFROOT/texmf-dist/scripts/texlive");
+  unshift(@INC, "HOMEBREW_PREFIX/share/texlive-core/tlpkg", "HOMEBREW_PREFIX/share/texlive-core/texbrew/scripts/texlive");
   require "mktexlsr.pl";
   TeX::Update->import();
 }
diff --git a/texk/texlive/linked_scripts/texlive/updmap.pl b/texk/texlive/linked_scripts/texlive/updmap.pl
--- a/texk/texlive/linked_scripts/texlive/updmap.pl
+++ b/texk/texlive/linked_scripts/texlive/updmap.pl
@@ -24,7 +24,7 @@ BEGIN {
     die "$0: kpsewhich -var-value=TEXMFROOT failed, aborting early.\n";
   }
   chomp($TEXMFROOT);
-  unshift(@INC, "$TEXMFROOT/tlpkg");
+  unshift(@INC, "HOMEBREW_PREFIX/share/texlive-core/tlpkg");
 }
 
 my $lastchdate = '$Date: 2017-05-14 04:15:43 +0200 (Sun, 14 May 2017) $';
