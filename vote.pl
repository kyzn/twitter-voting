#!/usr/bin/perl

#Copyright (C) 2015 Kivanc Yazan
#See LICENSE file for more details about GNU General Public License.

#Refer to readme.md file to understand how this script works.
#You can always reach/contribute to this open-source code at github.com/kyzn/twitter-voting

use utf8;
use warnings;
use strict;
use Modern::Perl;
use AnyEvent::Twitter::Stream; #capture twitter stream
use DateTime::Format::Strptime; #convert twitter time to perl time
use DateTime::Format::DBI; #convert perl time to mysql time
use DBI(); #mysql connection, db has to be ut8mb4! (refer to setup.sql)
use Math::Round; #we wanted to show the percentage somewhere

use Data::Dumper;

our $VERSION=0.1;

#Upon exiting with ctrl+c, we will close connections and
# more importantly, display the results.
$SIG{INT}  = \&disconnect;

#Used for Turkish character conversion
my @trchar=('ö','Ö','ç','Ç','ş','Ş','ı','İ','ğ','Ğ','ü','Ü');
my @nontrc=('o','O','c','C','s','S','i','I','g','G','u','U');

#Set default keywords to be tracked. They will be replaced by arguments if any given.
my $event_keyword = "myEvent2015";
my @team_keywords = qw/
altunizade
bakirkoy
beyoglu
bostanci
dolmabahce1
dolmabahce2
fatih
gayrettepe
izmit
kalamis
taksim
tuzla
/;


#Official applications (or at least most of them) are listed here.
# Votes casted only from these applications will be evaluated.
# This will be a measure against automated bot-cyborg use.
my @legal_sources = (
'<a href="http://twitter.com/download/android" rel="nofollow">Twitter for Android</a>',
'<a href="https://twitter.com/download/android" rel="nofollow">Twitter for Android Tablets</a>',
'<a href="http://twitter.com/download/iphone" rel="nofollow">Twitter for iPhone</a>',
'<a href="http://twitter.com/#!/download/ipad" rel="nofollow">Twitter for iPad</a>',
'<a href="http://www.twitter.com" rel="nofollow">Twitter for Windows Phone</a>',
'<a href="http://twitter.com" rel="nofollow">Twitter Web Client</a>',
'<a href="http://mobile.twitter.com" rel="nofollow">Mobile Web</a>',
'<a href="https://mobile.twitter.com" rel="nofollow">Mobile Web (M2)</a>',
'<a href="https://mobile.twitter.com" rel="nofollow">Mobile Web (M5)</a>',
'<a href="http://blackberry.com/twitter" rel="nofollow">Twitter for BlackBerry®</a>',
'<a href="http://www.twitter.com" rel="nofollow">Twitter for BlackBerry</a>',
'<a href="http://itunes.apple.com/us/app/twitter/id409789998?mt=12" rel="nofollow">Twitter for Mac</a>'
);

#Legal limit for a vote is defaulted to one week.
#You may change it as you wish.
my $legal_days = 7;
#That means, Twitter accounts newer than one week cannot vote whatsoever.
my $legal_limit = DateTime->now->subtract(days=>$legal_days);

#Valid vote prefix is used to distinguish invalid votes from valid ones,
# hence it would be better to pick something that is not starting with 'not'.
# 'not' keyword will be the beginning of invalid votes.
# Default valid vote prefix is set to 'team', but it may be changed as you wish.
# This prefix is also called in a SQL query, so cautions might be taken.
my $valid_vote_prefix="team";

#If at least one argument has been passed, replace the first one with default event keyword.
if(@ARGV>0){
	$event_keyword = shift(@ARGV);
}

#If there are more arguments passed, replace them with default team keywords.
if(@ARGV>0){
	#clear default team keywords
	@team_keywords = qw//;
}

while(@ARGV>0){
	#take from arguments, append to end of team keywords
	push @team_keywords, shift(@ARGV);
}


#Printing introduction, and what to track.
print "
-------------------------------------------------------------------------------
Twitter-Voting version $VERSION Copyright (C) 2015 Kivanc Yazan

Twitter-Voting comes with ABSOLUTELY NO WARRANTY; for details see LICENSE file.
This is free software, and you are welcome to redistribute it
under certain conditions; see LICENSE file for details.
-------------------------------------------------------------------------------

>> Now tracking for: #$event_keyword
>> Teams are ";
foreach (@team_keywords){
	print "#$_ ";
}

#Importing authentication variables from "TwitAuth.pm" file
#This is to have a working db connection and twitter stream. 
#Please check TwitAuth_sample.pm for an example.
use TwitAuth;

#This hash will store authentication details.
my %twa=getTwitAuth();


#Connect to the db.
my $dbh = DBI->connect("DBI:mysql:database=$twa{db_name};host=$twa{db_host}",
	$twa{db_user},$twa{db_pass},
	{'RaiseError' => 1, 
	mysql_enable_utf8 => 1,
	Callbacks => {
        connected => sub {
            $_[0]->do('SET NAMES utf8mb4');
            return;
        	}
    	}
    });


#Control if the database is empty or not. Issue a warning if not empty.
my $sth_empty = $dbh->prepare("SELECT COUNT(*) as num FROM tweets;");
	$sth_empty->execute();
	my $ref_empty = $sth_empty->fetchrow_hashref();
	my $initial_num_votes = $ref_empty->{'num'};
	$sth_empty->finish();
	if($initial_num_votes>0){
print "

----------WARNING----------
Tweets table in DB is NOT empty.
Results to be displayed might NOT be correct.
You may want to restart program after cleaning your db.
---------------------------
";
	}


#strp and db_parser are variables used to convert time formats
#convert twitter time to perl datetime
my $strp = DateTime::Format::Strptime->new(pattern => '%a %b %d %T %z %Y');
#convert perl datetime to twitter time
my $db_parser = DateTime::Format::DBI->new($dbh);

#done and listener are variables related to twitter streamer.
#when a tweet is received "incoming" is called.
my $done = AnyEvent->condvar;
my $listener = AnyEvent::Twitter::Stream->new(
	consumer_key    => $twa{consumer_key},
	consumer_secret => $twa{consumer_secret},
	token           => $twa{token},
	token_secret    => $twa{token_secret},
	method          => "filter",
	track           => $event_keyword,
	on_tweet        => \&incoming,
	on_error => \&error,
	timeout  => 60
);

print "

Listening to Twitter.
Username\tStatus
";

$done->recv;
#next line will be run on timeout errors
$dbh->disconnect();

#subroutine to be called when a tweet is received
#a tweet is to be inserted into the database.
sub incoming{

	#pick the tweet
	my $tweet = shift;
	
	#if there is a problem with the tweet, don't deal with it
	#this prevents script to stop working when a message comes from twitter
	# such as deletion notice, limit notice etc.
	return unless ($tweet->{id});
	
	#all negative vote indicators will start with not-
	#default vote indicator would be 'not-processed'
	my $vote_indicator="not-processed";
	my $possible_team ="";
	my $num_of_teams  =0;
	my $num_of_votes  =0;

	#There is a priority in invalid votes. Once we understand a vote is invalid,
	# we stop making controls. For example, if we know a tweet is sent from a 
	# rather recent account, we don't check whether it's a retweet or not.
	# Incorrect numbers of types of invalid votes would be a consequence of this.
	# We may develop an approach to see all reasons that makes a tweet invalid,
	# or we may simply say "this is invalid" and leave the reason behind us.
	# All these are possible improvements. Please do send pull requests if you
	# have time to work on such features.

	#compare all hashtags in tweet against team keywords
		
	foreach my $hashtag (@{$tweet->{entities}{hashtags}})
	{
		my $hash_text = $hashtag->{text};

		#remove turkish characters
		for(my $i=0;$i<@trchar;$i++){
			$hash_text=~s/$trchar[$i]/$nontrc[$i]/g;
		}

 		#convert to lowercase
        $hash_text=lc($hash_text);

		foreach my $team_key (@team_keywords){
			if ($team_key eq $hash_text){
				$possible_team=$hash_text;
				$num_of_teams++;
			} 
		}
	}

	#control if the user already has a valid vote in the db 
	#TODO this sql statement might be subject to injection attacks!
	my $sth2 = $dbh->prepare("SELECT COUNT(*) as num FROM tweets 
		WHERE UserID = $tweet->{user}{id} AND Status LIKE '$valid_vote_prefix%';");
  		$sth2->execute();
  		my $ref = $sth2->fetchrow_hashref();
    	if($ref->{'num'}>0){
    		$num_of_votes=$ref->{'num'};
    	}
  		$sth2->finish();

	#not-old-enough: the account is created in a week, the vote is not valid.
	if($strp->parse_datetime($tweet->{user}{created_at}) > $legal_limit){
		$vote_indicator = "not-old-enough";
	}

	#not-original: is a retweet
	elsif($tweet->{text} =~ /^RT @/){
		$vote_indicator="not-original";
	}

	#not-single-team: tweet either does not contain any team, or contains more than one.
	elsif($num_of_teams!=1){
		$vote_indicator="not-single-team";
	}
				
	#not-human: tweet is not posted through official applications.
	elsif(!($tweet->{'source'} ~~ @legal_sources)){
		$vote_indicator="not-human";
	}

	#not-first-vote: user has already voted, hence he/she can send no more vote.
	elsif($num_of_votes>0){
		$vote_indicator="not-first-vote";
	}


	#If no invalidity is found until this point, mark the tweets as a valid vote.
	#All valid votes will look like team-{team-keyword} (eg. team-xyz)
	if ($vote_indicator eq "not-processed"){
		$vote_indicator = $valid_vote_prefix."-".$possible_team;
	}else{ 
		$possible_team="";
	}

	#insert tweet into db
	$dbh->do("INSERT INTO tweets (TweetID,TweetText,TweetDT,TweetApp,UserID,UserName,UserDT,Status) 
		VALUES (?,?,?,?,?,?,?,?);", 
	undef, 
	$tweet->{id}, #id of tweet, bigint
	unicodefix($tweet->{text}),
	$db_parser->format_datetime($strp->parse_datetime($tweet->{created_at})),
	$tweet->{source},
	$tweet->{user}{id},
	unicodefix($tweet->{user}{screen_name}),
	$db_parser->format_datetime($strp->parse_datetime($tweet->{user}{created_at})),
	$vote_indicator
	);

	#Watching incoming tweets can be fun.
	print "\@$tweet->{user}{screen_name}\t$vote_indicator\n";


}

#subroutine to be called when an error occurs
sub error{
	my $error = shift;
	warn "ERROR: $error";
	$done->send;
}

#subroutine to be called on exiting through sigint (ctrl+c)
sub disconnect(){

	#Get total number of votes
	my $sth3 = $dbh->prepare("SELECT COUNT(*) as total FROM tweets;");
	$sth3->execute();
	my $ref3 = $sth3->fetchrow_hashref();
	my $total_votes = $ref3->{'total'};
	$sth3->finish();

	#Get total number of 'valid' votes
	$sth3 = $dbh->prepare("SELECT COUNT(*) as total_valid FROM tweets WHERE Status LIKE '$valid_vote_prefix%';");
	$sth3->execute();
	$ref3 = $sth3->fetchrow_hashref();
	my $total_valid_votes = $ref3->{'total_valid'};
	$sth3->finish();

	my $percent = round(100*$total_valid_votes/$total_votes);

	print "

RESULTS
Total number of votes......: $total_votes
Total number of valid votes: $total_valid_votes
Percentage of valid votes..: $percent%

TEAMS
";

	#Get vote counts for each team
	$sth3 = $dbh->prepare("SELECT COUNT(*) as num, Status FROM tweets WHERE Status 
		LIKE '$valid_vote_prefix%' GROUP BY Status ORDER BY num DESC;");
	$sth3->execute();
	while($ref3 = $sth3->fetchrow_hashref()){
		print $ref3->{'Status'}."\t".$ref3->{'num'}." votes\n";
	}
	$sth3->finish();

	#Finally, display invalid votes.
	print "\nINVALID VOTES\n";
	$sth3 = $dbh->prepare("SELECT COUNT(*) as num, Status FROM tweets WHERE Status 
		LIKE 'not%' GROUP BY Status ORDER BY num DESC;");
	$sth3->execute();
	while($ref3 = $sth3->fetchrow_hashref()){
		print "$ref3->{'num'} votes were $ref3->{'Status'}.\n";
	}

	#Now we can exit in peace.
	$sth3->finish();
	print "\nDisconnecting..";
	$dbh->disconnect();
	$done->send;
	print ".\n";
}


#subroutine to fix ascii smilies
# This was actually developed for some other twitter related work, but there you go.
sub unicodefix(){
	my ($tweet) = @_;
	#Unicode reserved blocks are
	#d800-dfff surrogate pairs
	#fe00-fe0f variation selector

	#single unicode characters without a starting d
	$tweet=~s/\\u([0-9abcABCefEF].{3})/chr(eval("0x$1"))/eg;

	#single unicode characters with a starting d (not in the reserved zone)
	$tweet=~s/\\u([dD][0-7].{2})/chr(eval("0x$1"))/eg;

	#unicode surrogate pairs (reserved zone)
	$tweet=~s/\\u([dD][89a-fA-F].{2})\\u([dD][89a-fA-F].{2})/
		chr(eval(hex("0x10000") + (hex($1) - hex("0xD800"))* 
		hex("0x400")+ (hex($2) - hex("0xDC00"))->as_hex))/eg;

	return $tweet;
}