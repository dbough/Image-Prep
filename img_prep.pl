#!/usr/bin/perl
# Download, Resize, and update EXIF tags on Images
use warnings;
use strict;
use Image::ExifTool qw(:Public);
use Image::Grab;
use Text::CSV;
use File::Path qw(make_path);
use Getopt::Long;
use URI;
use Domain::PublicSuffix;

use Data::Dumper;

my $debug = 0;
my $target_directory;
my $csv_file;
my $images = ();

GetOptions (
	"target_directory=s" => \$target_directory,
	"csv_file=s"   => \$csv_file,
	"debug"  => \$debug,
	"help" => \&help
);

# Make sure we have these things or we cant go on
if (!$target_directory || !$csv_file ) {
	print "Need target directory and CSV file!" if $debug;
	&help;
}

# Create target_directory if it doesn't exist ( and make sure it has a trailing forward slash)
my $last_char = chop($target_directory);
if ($last_char ne "/") {
	$target_directory .= "/";
}
make_path($target_directory);

# Import CSV (url, image_name)
my $csv = Text::CSV->new ( { binary => 1 } ) or die "Cannot use CSV: ".Text::CSV->error_diag ();
print "Grabbing config file " . $csv_file . "\n" if $debug;
open my $fh, $csv_file or die "$csv_file: $!";
my $header_skipped = 0;
while ( my $row = $csv->getline( $fh ) ) {
	# Skip the header row
	if ($header_skipped <= 0) {
		$header_skipped = 1;
		next;
	}
	push @{ $images }, {
		url => $row->[0],
		image_name => $row->[1],
		desc => $row->[1]
	};
}
$csv->eof or $csv->error_diag();
close $fh;

print "Images array: " if $debug;
print Dumper $images if $debug;
print "\n\n" if $debug;

# Download urls
foreach my $image ( @{ $images } ) {

	# Create source name
	$image->{ source } = &create_image_source( $image->{ url } );

	# Create file name
	$image->{ file_name } = &create_file_name( $image->{ image_name } );

	# Download Image
	my $raw_image = &download_image( $image->{ url } );
	
	# Save Image
	&save_image( $raw_image, $image->{ file_name } );

	# Resize Image
	&resize_image($image->{ file_name });
	
	# Update meta tags
	&update_exif($image);

	print "\n\n" if $debug;
}

print "Done!\n";
exit(0);
#------------------------------------------

# Create source url from long url
# @param string $url: $url to shorten
# @return string $to_return:  Shortened URL
# Exmample:  http://www.kittens.com/image.jpg would be shortened to kittens.com
sub create_image_source {
	my $full_url = shift;
	my $url = URI->new( $full_url );
	my $domain = $url->host;
	my $suffix = Domain::PublicSuffix->new();
 	my $to_return = $suffix->get_root_domain($domain);

	return $to_return;
}

# Create file name from image name 
# @param string $image_name:  Image name
# @return string $file_name (lowercase $image_name with underscores instead of spaces)
sub create_file_name {
	my $image_name = shift;
	print "Creating file name from " . $image_name . "... " if $debug;
	$image_name =~ s/ /_/g;
	my $file_name = lc( $image_name . '.jpg' );
	print $file_name . "\n" if $debug;

	return $file_name;
}

# Download image to $target_directory
# @param string $url:  URL of an image to download
# @return $image_data->image: encoded image
sub download_image {
	my $url = shift;
	print "Downloading image from " . $url . "\n" if $debug;
	my $image_data = Image::Grab->new( URL=>$url );
	my $user_agent = 'Mozilla/5.0 (compatible, MSIE 11, Windows NT 6.3; Trident/7.0; rv:11.0) like Gecko';
	$image_data->ua->agent($user_agent);
	$image_data->grab;

	return $image_data->image;
}

# Save image to target_directory
# @param $raw_image = encoded image
# @param string $file_name = What to name the image
sub save_image {
	my $raw_image = shift;
	my $file_name = shift;
	my $full_path = $target_directory . $file_name;
	print "Saving file:" . $full_path . "\n" if $debug;
	open(IMAGE, ">" . $full_path ) or die "$full_path : $!";
	print IMAGE $raw_image;
	close IMAGE;
}

# Resize images so that longest side is 600px
# @param string $file_name: name of file to resize
sub resize_image {
	my $file_name = shift;
	my $full_path = $target_directory . $file_name;
	# Need to find a better way to do this?  The Image libraries don't seem to want to install on Mac
	print "Resizing file:" . $full_path . "\n" if $debug;
	my $command = "/usr/bin/sips -Z 600 " . $full_path . " 2>/dev/null";
	my $result = `$command`;
}

# Update EXIF info of photo
# @param hashref $image:  Hashref of image info
sub update_exif {
	my $image = shift;
	my $exif_tool = new Image::ExifTool;
	my $file_path = $target_directory . $image->{ file_name };
	
	# Overwrite existing meta tags
	print "Overwriting EXIF tags for " . $image->{ file_name } . "\n" if $debug;
	$exif_tool->SetNewValue('*');

	# Set EXIF info for 
	# IPTC:Headline (Image Name)
	# IPTC:DocumentNotes (Image Name)
	# IPTC:LocalCaption (Source)
	# EXIF:ImageDescription (Description)
	# TODO.  Add error handling
	# ($success, $errStr) = $exif_tool->SetNewValue($tag, $value);
	print "Setting EXIF tags for " . $file_path . "\n" if $debug;
	my $headline = $image->{ image_name };
	$headline =~ s/ /_/g;
	$exif_tool->SetNewValue('IPTC:Headline', $headline);
	$exif_tool->SetNewValue('IPTC:DocumentNotes', $image->{ image_name });
	$exif_tool->SetNewValue('IPTC:LocalCaption', $image->{ source });
	$exif_tool->SetNewValue('EXIF:ImageDescription', $image->{ desc });

	# Write info to file
	print "Saving EXIF info for " . $file_path . "\n" if $debug;
	$exif_tool->WriteInfo($file_path);
}

# Print help and exit
sub help {
	my $to_print = "\nDescription:  Download images from URLs and overwrite their meta tags.\n";
	$to_print .= "Usage: ";
	$to_print .= $0 . " --target_directory='/put/images/here' --csv_file='/path/to/csv' --debug\n\n";
	print $to_print;
	exit(0);
}
