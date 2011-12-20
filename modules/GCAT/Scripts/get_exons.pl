#!/usr/bin/env perl

# Genome Comparison and Analysis Toolkit
#
# An adaptable and efficient toolkit for large-scale evolutionary comparative genomics analysis.
# Written in the Perl programming language, GCAT utilizes the BioPerl, Perl EnsEMBL and R Statistics
# APIs.
#
# Part of a PhD thesis entitled "Evolutionary Genomics of Organismal Diversity".
#
# Coded by Steve Moss
# gawbul@gmail.com
#
# C/o Dr David Lunt and Dr Domino Joyce,
# Evolutionary Biology Group,
# The University of Hull.

=head1 NAME

	get_exons

=head1 SYNOPSIS

    get_exons species1 species2 species3...
    
=head1 DESCRIPTION

	A program to retrieve all exon sequences from all genes, for a given number of species.

=cut

# import some modules to use
use strict;
use Bio::Seq;
use Bio::SeqIO;
use Time::HiRes qw(gettimeofday tv_interval);
use Parallel::ForkManager; # used for parallel processing
use GCAT::Interface::Logging qw(logger); # for logging
use GCAT::DB::EnsEMBL;
use Cwd;
use File::Spec;
use Log::Log4perl::DateFormat;


# define variables
our $index = 0;

# get root directory and create data directory if doesn't exist
my $dir = getcwd();
mkdir "data" unless -d "data";

# get arguments
my $num_args = $#ARGV + 1;
my @organisms = @ARGV;

# check arguments list is sufficient
if ($num_args < 1) {
	logger("This script requires at least one input argument, for the organisms you wish to download the information for.", "Error");
	exit;
}

# tell user what we're doing
print "Going to retrieve exons for $num_args species: @organisms...\n";

# set start time
my $start_time = gettimeofday;

# connect to EnsEMBL and setup registry object
my $registry = connect_to_EnsEMBL;

# set autoflush for stdout
local $| = 1;

# setup fork manager
my $pm = new Parallel::ForkManager(8);

# go through all fish and retrieve exon ids and coordinates
my $count = 0;
foreach my $org_name (@organisms) {
	# start fork
	my $pid = $pm->start and next;
	
	# setup output filename
	mkdir "data/$org_name" unless -d "data/$org_name";
	my $path = File::Spec->catfile($dir, "data", "$org_name", "exons.fas");
	my $seqio_out = Bio::SeqIO->new(-file => ">$path" , '-format' => 'Fasta');
	
	# setup DB adapters
	my $gene_adaptor = $registry->get_adaptor($org_name, 'Core', 'Gene');
	my $tr_adaptor    = $registry->get_adaptor($org_name, 'Core', 'Transcript');
	
	# get current database name
	my $db_adaptor = $registry->get_DBAdaptor($org_name, "Core");
	my $dbname = $db_adaptor->dbc->dbname();
	my $release = $dbname;
	$release =~ m/[a-z]+_[a-z]+_core_([0-9]{2})_[0-9]{1}/;
	$release = int($1);

	# let user know we're starting
	my $printed = 0;
	print "Retrieving gene IDs for $dbname...\n";
	
	# retrieve all stable IDs
	my @geneids = &get_Gene_IDs($registry, $org_name);
	my $gene_count = $#geneids + 1;
	
	# go through each gene stable ID and retrieve canonical transcript and exons
	foreach my $geneid (@geneids)
	{
		if ($printed == 0) {
			print "Retrieving exons for $dbname...\n";
			$printed = 1;
		}
		
		# fetch the gene by stable id
		my $gene = $gene_adaptor->fetch_by_stable_id($geneid);

		# only get protein coding genes
		unless ($gene->biotype eq "protein_coding") {
			next;
		}
		
		# setup transcript adaptor to retrieve exons
		my $tr = $gene->canonical_transcript();		

		# get all exons for the gene canonical transcript
		my $exons = $tr->get_all_Exons();
		
		# traverse exons
		while (my $exon = shift @{$exons}) {
			# build the bio seq object
			my $exon_obj = Bio::Seq->new( 	-primary_id => $exon->stable_id(),
											-display_id => $exon->stable_id(),
											-desc => $gene->stable_id() . " " . $tr->stable_id() . " " . $exon->start() . " " . $exon->end() . " " . $exon->length() . " " . $exon->strand(),
											-alphabet => 'dna',
											-seq => $exon->seq->seq);
											
			# write the fasta sequence
			# unless we have a 0 length exon
			if ($exon->length() == 0) {
				next;
			}
			
			$seqio_out->write_seq($exon_obj);
			
			# let user know something is happening
			if ($count % 1000 == 0) {
				print "."
			}
			$count++;
		}
	}
	print "\nRetrieved $count exons for $org_name.\n";
	
	# finish fork
	$pm->finish;
}

# wait for all processes to finish
$pm->wait_all_children;

# set end time and calculate time elapsed
my $end_time = gettimeofday;
my $elapsed = $end_time - $start_time;

# let user know we have finished
printf "Finished in %0.3f!\n", $elapsed;
