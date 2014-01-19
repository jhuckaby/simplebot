SimpleBot
=========

SimpleBot is an easy-to-install and easy-to-use general purpose IRC bot, written in Perl.  It is built on the awesome [Bot::BasicBot](http://search.cpan.org/dist/Bot-BasicBot/) framework.

Features at a glance:

* Single-command install on most flavors of Linux
* Alarm clock, countdown to date/time, timer
* Google Calendar integration with countdown to events
* Google Search commands for searching and defining terms
* Weather system for current conditions and 5-day forecast
* Twitter integration for automatically following or retweeting
* Custom topic system for defining a set of columns and a divider
* FAQ system to define custom commands that emit text
* Scoreboard system for awarding points to users
* Poll system with user voting
* Calculator and unit converter
* Version check and self-upgrade commands
* Network utilities such as ping, DNS lookup, URL sniff
* Custom greetings and goodbyes for users
* Insult generator (have the bot insult a user)
* Custom access level control for all commands (voice, half, op, etc.)
* Custom activator symbols (exclamation point, etc.)
* Configuration editing system from within IRC
* Administrative commands including nick, join, restart, quit, upgrade, etc.
* Puppet mode (have the bot say anything in any channel, sent from a PM)
* Integrated help text for all commands
* Database implemented with simple JSON files on disk

## Single-Command Install

To install SimpleBot, execute this command as root on your server:

    curl -s "http://pixlcore.com/software/simplebot/install-latest-stable.txt" | bash

Or, if you don't have curl, you can use wget:

    wget -O - "http://pixlcore.com/software/simplebot/install-latest-stable.txt" | bash

This will install the latest stable version of SimpleBot.  Change the word "stable" to "dev" to install the development branch.  This single command installer should work fine on any modern Linux RedHat (RHEL, Fedora, CentOS) or Debian (Ubuntu) operating system.  Basically, anything that has "yum" or "apt-get" should be happy.  See the manual installation instructions for other OSes, or if the single-command installer doesn't work for you.

After installation, you will be provided instructions for connecting to a server for the first time.  If you are running our sister product, [SimpleIRC](https://github.com/jhuckaby/simpleirc), on the same server as SimpleBot, this will be detected and everything automatically set up and connected for you.

## Copyright and Legal

SimpleBot is copyright (c) 2013 by Joseph Huckaby and PixlCore.com.  It is released under the MIT License (see below).

SimpleBot relies on the following non-core Perl modules, which are automatically installed, along with their prerequisites, using [cpanm](http://cpanmin.us):

* POE
* Bot::BasicBot
* JSON::XS
* LWP::UserAgent
* URI::Escape
* HTTP::Date
* DateTime
* DateTime::TimeZone
* DateTime::TimeZone::Alias
* Net::Twitter::Lite
* Net::Ping::External
* Math::Units

### Plugin APIs

The bot's Weather Plugin uses a free API available from WorldWeatherOnline.com.  You will need to sign up for a free account and get an API Key in order to use this Plugin.  For instructions, type "!help weather" in a channel where the bot is, or "/msg simplebot help weather" on the IRC console.

The bot's Twitter Plugin uses the free Twitter API v1.1.  For this, you will need to sign up for a Twitter account, and create a free "application" on dev.twitter.com, in order to get API keys and use the Plugin.  For instructions, type "!help twitter" in a channel where the bot is, or "/msg simplebot help twitter" on the IRC console.

### MIT License

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

