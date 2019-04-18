Twitter Voting
===============

This app is intended to be used in events, where organizer wants to hold public voting through Twitter. Originally, the script has been developed for an event titled 'Rotaart 2015' that was held in Istanbul.

# Requirements

You will obviously need Perl installed on your system. Most probably it's installed by default.

MySQL will be utilized too, but you will need at least v5.5.3. This is because we will have `utf8mb4` encoding, and prior versions will not support.
We need several CPAN modules too. You can install all dependencies by running following code block on your terminal/shell.

```bash
sudo cpan install Modern::Perl Net::SSLeay Net::OAuth AnyEvent::Twitter::Stream DBD::mysql DateTime::Format::Strptime DateTime::Format::DBI DateTime::Format::MySQL Math::Round
```

# Initial Setup
1. You have to setup your database. Run setup.sql on your MySQL.
2. Copy TwitAuth_sample.pm as TwitAuth.pm
3. Write your db credentials into TwitAuth.pm
4. You need to create a Twitter application at [Twitter Apps](http://apps.twitter.com). Read-only permission would be enough.
5. Copy Twitter tokens to TwitAuth.pm as well.


# How it Works
The organizer decides on a **event keyword**. For example, let it be *myEvent2015*. This keyword is given to the Twitter Streaming API, which means we track all real time tweets sent with the decided key. Of course, the API has its limitations, so the application may not work  properly if you decide to use it for an event that millions of people are willing to vote.

Then, the organizer should decide on **team keywords**. For sake of simplicity, let them be *xx*, *yy*, *zz*, and *tt*. Organizer have to ask participant to post their votes as follows: Include event keyword and one of the team keywords. Let us make it clear by giving an example.

 > \#myEvent2015 is so much fun!

This tweet will be catched by the application, but will not be considered as a vote. See restrictions for more.

> \#myEvent2015 go \#xx ! we <3 u

This will be a valid vote, as it both includes event and team keyword as hashtag.

There is also a mechanism that converts incoming hashtags that user wrote to lowercase. The same piece of code also converts Turkish characters to their Latin correspondant (eg. ç becomes c), so you might want to pick you team keywords accordingly.

# How to Use

You can just run `vote.pl` by executing `perl vote.pl` in the folder where code exists. The default event-keyword and team-keywords are set to *rotaart2015* and 12 original participant teams, so you might want to change them. There is an easier way: You can pass them as arguments. First argument will be event keyword, and the rest will be team keywords. An example can be found below:

`perl vote.pl myEvent2016 red blue green`would run the application with event keyword *myEvent2016* and team keywords *red*, *blue*, *green*. 


When you're done, you can send a sigint by ctrl+c. Upon exiting, application will print you results.

# Restrictions
In order to prevent abuse, we have set several restrictions.

## not-old-enough
Twitter accounts that are created in the last week will not be able to vote. (7 days of default might be changed, find ```$legal_days``` in ```vote.pl```.

## not-original

A ReTweet will not be counted as a vote. We kindly ask participants to create their original content.

## not-single-team
If a Tweet does not contain exacly one team keyword in its hashtags, this error will be raised. Here are some examples.

>\#myEvent2015 \#four

>\#myEvent2015 \#three \#four

First one is a legal vote since it contains the event hashtag + only one kind of team hashtag. However, the second content will not be considered as a valid vote.

## not-human
If a Tweet is not sent from selected applications, it will not be considered as a vote. Find `@legal_sources` in `vote.pl` to change the list. The current list is as follows:


 * Twitter for Android
 * Twitter for Android Tablets
 * Twitter for iPhone
 * Twitter for iPad
 * Twitter for Windows Phone
 * Twitter Web Client
 * Mobile Web
 * Mobile Web (M2)
 * Mobile Web (M5)
 * Twitter for BlackBerry®
 * Twitter for BlackBerry
 * Twitter for Mac


## not-first-vote
We will count only one legal vote from a Twitter user. The control is done by userid, so
even if user changes the username, the restriction will still be applied.

### All invalid votes will be shown with a *not-* prefix. There is another prefix for valid votes, too. It is defaulted to *team-*, but you may change it if you wish. Look for `$valid_vote_prefix` in `vote.pl`.


## Known Issues

1. As a measure of Twitter Streaming API, we cannot count votes casted from protected accounts. We may ask participants to remove the protection for a little time, cast their vote and apply the protection again, but participants might not be ok with this. This is more of a limitation than a known issue.

2. Turkish or Japanese characters in event-keyword cause application to fail.

3. As described in `vote.pl` too, there is a priority in invalid votes. Once we understand a vote is we stop making controls. This leads to incorrect numbers for types of invalid votes.

4. There are possible vulnerabilities for SQL Injection attacks. We use strings in several SQL statements, which is not good.

5. When quitting the program with ctrl+c, you may see database errors if there are huge number of incoming tweets at the instant.


## Copyright and Licence

Copyright (C) 2015 Kivanc Yazan

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy (see LICENSE file) of the GNU General Public License
along with this program; if not, write to the Free Software Foundation, Inc.,
51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
