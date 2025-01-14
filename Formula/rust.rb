class Rust < Formula
  desc "Safe, concurrent, practical language"
  homepage "https://www.rust-lang.org/"
  license any_of: ["Apache-2.0", "MIT"]

  stable do
    url "https://static.rust-lang.org/dist/rustc-1.48.0-src.tar.gz"
    sha256 "0e763e6db47d5d6f91583284d2f989eacc49b84794d1443355b85c58d67ae43b"

    resource "cargo" do
      url "https://github.com/rust-lang/cargo.git",
          tag:      "0.49.0",
          revision: "65cbdd2dc0b7e877577474b98b7d071308d0bb6f"
    end
  end

  bottle do
    cellar :any
    sha256 "9658dfa0ecf5f57b14223b56d60c4d303db1939174ae3bd9c3aea2918c3fafb6" => :big_sur
    sha256 "643cb64baa823b8db5e7a4848ec157f45811db9891a641569a3963b0a6d75c6d" => :catalina
    sha256 "5d24baae2f6e47a826849f61b7ac370dcfd3616802617b41a82501cc576e9e3f" => :mojave
    sha256 "eba5a173f9a7db88af4999c3ba1743cf564d31f367a5c941147306cb39797ae2" => :high_sierra
  end

  head do
    url "https://github.com/rust-lang/rust.git"

    resource "cargo" do
      url "https://github.com/rust-lang/cargo.git"
    end
  end

  depends_on "cmake" => :build
  depends_on "ninja" => :build
  depends_on "python@3.9" => :build
  depends_on "libssh2"
  depends_on "openssl@1.1"
  depends_on "pkg-config"

  uses_from_macos "curl"
  uses_from_macos "zlib"

  resource "cargobootstrap" do
    on_macos do
      # From https://github.com/rust-lang/rust/blob/#{version}/src/stage0.txt
      url "https://static.rust-lang.org/dist/2020-11-19/cargo-1.48.0-x86_64-apple-darwin.tar.gz"
      sha256 "ce00d796cf5a9ac8d88d9df94c408e5d7ccd3541932a829eae833cc8e57efb15"
    end

    on_linux do
      # From: https://github.com/rust-lang/rust/blob/#{version}/src/stage0.txt
      url "https://static.rust-lang.org/dist/2020-11-19/cargo-1.48.0-x86_64-unknown-linux-gnu.tar.gz"
      sha256 "52bf632e337a5e7464cb961766638e30dfa28edb3036428296678d1aaf7d8ede"
    end
  end

  def install
    ENV.prepend_path "PATH", Formula["python@3.9"].opt_libexec/"bin"

    # Fix build failure for compiler_builtins "error: invalid deployment target
    # for -stdlib=libc++ (requires OS X 10.7 or later)"
    ENV["MACOSX_DEPLOYMENT_TARGET"] = MacOS.version

    # Ensure that the `openssl` crate picks up the intended library.
    # https://crates.io/crates/openssl#manual-configuration
    ENV["OPENSSL_DIR"] = Formula["openssl@1.1"].opt_prefix

    # Fix build failure for cmake v0.1.24 "error: internal compiler error:
    # src/librustc/ty/subst.rs:127: impossible case reached" on 10.11, and for
    # libgit2-sys-0.6.12 "fatal error: 'os/availability.h' file not found
    # #include <os/availability.h>" on 10.11 and "SecTrust.h:170:67: error:
    # expected ';' after top level declarator" among other errors on 10.12
    ENV["SDKROOT"] = MacOS.sdk_path

    args = ["--prefix=#{prefix}"]
    if build.head?
      args << "--disable-rpath"
      args << "--release-channel=nightly"
    else
      args << "--release-channel=stable"
    end
    # Cross-compile arm64 with x86_64 bootstrap compiler.
    if Hardware::CPU.arch == :arm64
      args << "--build=x86_64-apple-darwin"
      args << "--host=aarch64-apple-darwin"
      args << "--target=aarch64-apple-darwin"
      system "./configure", *args
      system "arch", "-x86_64", "make"
    else
      system "./configure", *args
      system "make"
    end
    system "make", "install"

    resource("cargobootstrap").stage do
      system "./install.sh", "--prefix=#{buildpath}/cargobootstrap"
    end
    ENV.prepend_path "PATH", buildpath/"cargobootstrap/bin"

    resource("cargo").stage do
      ENV["RUSTC"] = bin/"rustc"
      args = %W[--root #{prefix} --path . --features curl-sys/force-system-lib-on-osx]
      system "cargo", "install", *args
      man1.install Dir["src/etc/man/*.1"]
      bash_completion.install "src/etc/cargo.bashcomp.sh"
      zsh_completion.install "src/etc/_cargo"
    end

    rm_rf prefix/"lib/rustlib/uninstall.sh"
    rm_rf prefix/"lib/rustlib/install.log"
  end

  def post_install
    Dir["#{lib}/rustlib/**/*.dylib"].each do |dylib|
      chmod 0664, dylib
      MachO::Tools.change_dylib_id(dylib, "@rpath/#{File.basename(dylib)}")
      chmod 0444, dylib
    end
  end

  test do
    system "#{bin}/rustdoc", "-h"
    (testpath/"hello.rs").write <<~EOS
      fn main() {
        println!("Hello World!");
      }
    EOS
    system "#{bin}/rustc", "hello.rs"
    assert_equal "Hello World!\n", `./hello`
    system "#{bin}/cargo", "new", "hello_world", "--bin"
    assert_equal "Hello, world!",
                 (testpath/"hello_world").cd { `#{bin}/cargo run`.split("\n").last }
  end
end
