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

### Plugin APIs

The bot's Weather Plugin uses a free API available from WeatherUnderground.com.  You will need to sign up for a free account and get an API Key in order to use this Plugin.  For instructions, type "!help weather" in a channel where the bot is, or "/msg simplebot help weather" on the IRC console.

The bot's Twitter Plugin uses the free Twitter API v1.1.  For this, you will need to sign up for a Twitter account, and create a free "application" on dev.twitter.com, in order to get API keys and use the Plugin.  For instructions, type "!help twitter" in a channel where the bot is, or "/msg simplebot help twitter" on the IRC console.

## Command Summary

* REGISTER - Attempt to register the bot nickname with NickServ.
* IDENTIFY - Attempt to identify with NickServ (happens automatically on connect).
* NICK - Change the bot's nickname permanently.
* MSG - Send a custom private message to any user (i.e. NickServ, ChanServ, etc.)
* ACCESS - Change user access levels for commands (set, get, list)
* OWNER - Change bot ownership (add, remove, list)
* ACTIVATOR - Change bot activator symbols (add, remove, list)
* SAY - Have the bot say something (puppet mode)
* EMOTE - Have the bot emote something.
* EVAL - Eval raw Perl code (for debugging only)
* EXEC - Execute raw shell command (for debugging only)
* JOIN - Have the bot join a channel (remembers, autojoins)
* LEAVE - Have the bot leave a channel (removes autojoin)
* CONFIG - Set or get configuration values.
* SAVE - Immediately save bot data to disk
* QUIT - Make the bot disconnect and shut down.
* RESTART - Make the bot restart itself.
* VERSION - Report current and latest available version of SimpleBot.
* UPGRADE - Upgrade SimpleBot to the latest version.
* AUTOKICK - Add, delete or list phrases that automatically kick users when spoken.
* CALC - Perform simple math calculations.
* CONVERT - Convert values between many known units (i.e. temp, weight, volume).
* RAND - Generate a random number given a maximum or range.
* ROLL - Roll dice for use in Roll Playing Games, such as Dungeons & Dragons.
* HASH - Generate MD5 hash of string, or a random source.
* PICK - Pick a random user from the channel, and notify them.
* TIME - Emits the current date/time in the user's local timezone (if known).
* ALARM - Sets single or repeating alarms which alert the user at the proper date/time.
* COUNTDOWN - Countdown to a particular time, date or next calendar event.
* TIMER - Simple countdown timer given minutes and seconds.
* TIMEZONE - Set your timezone for date/time related queries.
* QUAKES - Report most recent earthquake from USGS, and enable live quake monitoring.
* FAQ - Register a custom FAQ command which can be recalled at any time.
* CALENDAR - Attach a Google Calendar to the current channel, and show the current / next event.
* CURRENT - Show the current event from the channel's calendar, if any.
* NEXT - Show the next event on the channel's calendar and when it starts.
* HELLO - Set auto-greeting so bot says hello to you when you join.
* BYE - Set auto-goodbye so bot says goodbye to you after you leave.
* HELP - Show this help text.
* INSULT - Insult a user.
* LAST - Report when a user was last seen in a channel.
* PING - Pings a hostname to see if it responds, and reports the round trip time in milliseconds.
* HOST - Attempts to resolve a hostname to IP, or IP to hostname, using DNS.
* HEAD - Analyzes a given URL, and reports back its HTTP response headers (byte size, web server, etc.).
* TCP - Attempt a TCP socket connection on a given hostname/IP and port number.
* POINTS - Manage a "points" system to give special users credit.
* AWARD - Award points to a user.
* DEDUCT - Deduct points from a user.
* SCORES - Show the top scores or clears the list.
* POLL - Manage polls (open, close, results).
* VOTE - Cast your vote for an open poll.
* TOPIC - Set the channel topic in special named columns, separated by a divider.
* TWITTER - Follow people on twitter, or retweet someone's latest tweet.
* RT - Retweet the last tweet of any Twitter username.
* FOLLOW - Start following a Twitter username in the current channel.
* UNFOLLOW - Stop following a Twitter username in the current channel.
* FOLLOWING - List all users we are current following on Twitter.
* WEATHER - Get current conditions for US zip code, 'city state' or 'city country'.
* FORECAST - Set 5 day forecast for US zip code, 'city state' or 'city country'.
* LOCATION - Set your default location and time zone for future queries.
* GOOGLE - Perform Google search and return first result.
* IMAGE - Perform Google image search and return direct URL to first result.
* DEFINE - Define term using the Wikipedia API or DictionaryAPI.com.
* SPELL - Spell check a word (uses DictionaryAPI.com).
* URBAN - Define term using the Urban Dictionary API.
* STOCK - Grab stock quote given company symbol (uses Yahoo Finance API).

## Admin Group

### ACCESS

	ACCESS set command level
	ACCESS get command
	ACCESS list

This allows you to manipulate the minimum user access levels per each bot command.  For example, 'access set emote op' would only allow operators (and up) to access the 'emote' command.  Use 'access get emote' to determine the current access level for a command, or 'access list' to list levels for all commands.  Examples:

	!access set join owner
	!access get twitter
	!access list

### ACTIVATOR

	ACTIVATOR add symbol
	ACTIVATOR remove symbol
	ACTIVATOR list

This allows you to manipulate the activation symbols that the bot recognizes.  By default the bot listens to tilde ('~') and exclamation ('!') prefixed commands, but you may remove these and add others.  Any non-alphanumeric symbol is acceptable.  Example: activator add ^

### CONFIG

	CONFIG SET path value
	CONFIG GET path

This command lets you get or set configuration values, without having to directly edit the config files on the server.  The values are saved in the bot database, and overide the config file values when the bot starts up.  You do have to know the "path" of the configuration value you want to get/set, which can be a simple key name, or PluginName/ElementName for plugin configurations.  Examples:

	!config set server 127.0.0.1
	!config set port 6667
	!config set Weather/APIKey cxs2x8wb5eh8mydgf74qa4s
	!config set Twitter/AccessTokenSecret BqF4txQFOWvdgwxdKxaviJlx91gI6Xprks763j

### EMOTE

	EMOTE text
	EMOTE #channel text

Same as "say", but causes the bot to emote instead.

### EVAL

	EVAL code
This will evaluate (run) raw Perl code.  Use with extreme caution.  Bot owners only.

### EXEC

	EXEC command
This will execute the provided text as a shell command on the server.  Use with extreme caution.  Bot owners only.

### IDENTIFY

	IDENTIFY
	IDENTIFY password

This command makes the bot attempt to identify with NickServ.  This happens automatically upon connect, as long as a password is specified in the bot's config file.  The standard '/msg NickServ IDENTIFY PASSWORD" command is sent, unless otherwise specified on the command itself (i.e. you can enter a different password, or different arguments altogether, if the IRC server requires it).  Whatever you enter is then remembered for future connections on the same server.

### JOIN

	JOIN #channel
This will cause the bot to join the channel specified by #channel. Also, he will remember this and auto-join the channel whenever he connects.

### LEAVE

	LEAVE
	LEAVE #channel
This will cause the bot to leave a channel.  You can specify the channel by name, or omit it to have the bot leave the current channel.

### MSG

	MSG who message
Send a custom private message to any user.  This can be used to construct custom commands for NickServ or ChanServ.  For example: !msg NickServ REGISTER mypassword myemail.  However, see REGISTER command.

### NICK

	NICK newnick
This command changes the bot's nickname.  The new name is saved to disk, so the bot will always remember its current value, even after a restart.

### OWNER

	OWNER add username
	OWNER remove username
	OWNER list

This allows you to manipulate the list of bot "owners", which are users who always have full control over the bot and can execute every command, regardless of access level.  Note that a user must have at least Half-Op (+h) permissions to become a bot owner.  This is a protection system to prevent users from changing their nick to a known bot owner who is offline, and then trying to access the bot before the nick identify timeout occurs.

### QUIT

	QUIT
This will cause the bot to disconnect from the IRC server and shut down. It will NOT restart.

### REGISTER

	REGISTER
	REGISTER password email
	REGISTER any params needed

This command makes the bot attempt to register its nickname with NickServ.  The standard "/msg NickServ PASSWORD EMAIL" command is sent, using the password and email in the bot's config file, unless otherwise specified on the command itself.  If you like you can format your own REGISTER command, as required by the IRC server.  Bot owners only.

### RESTART

	RESTART
This will cause the bot to disconnect and reconnect to the IRC server.

### SAVE

	SAVE
This causes the bot to immediately save all data to disk.  Normally this process happens automatically in the background every minute, if any data has changed.  However, this command will jump the interval and save instantly.

### SAY

	SAY text
	SAY #channel text

Have the bot say something.  Include #channel to specify a channel, so for example you can tell the bot what to say in a private chat, and he'll emit the text on a specific channel.  Omit #channel and he'll just say it in the same context you spoke to him.

### UPGRADE

	UPGRADE
	UPGRADE branch
This command upgrades the bot to the latest available version on PixlCore.com.  If you enter the command by itself, it upgrades to the latest version in the current branch (i.e. stable, dev, etc.).  However, you can also switch branches using the upgrade command.  Just include the branch name after the command.
For example, if you are on the stable branch and want to switch to the bleeding-edge development branch, type: !upgrade dev

### VERSION

	VERSION
This will emit the current installed version of the SimpleBot software, as well as check PixlCore.com to see if there is a newer version available.

## Auto Kick Group

### AUTOKICK

	AUTOKICK add BADWORD
	AUTOKICK delete BADWORD
	AUTOKICK list

This allows you to set special words or phrases (regular expressions) that will automatically kick users if spoken.  Use '!autokick add WORD' to add a word or phrase to the list, '!autokick delete WORD' to remove one, and '!autokick list' to list them all.  The list is channel specific.

To change the message sent to users as they are kicked out, use this command:

	!config set AutoKick/KickMessage Your Message Here

## Calc Group

### CALC

	CALC expression
This command performs simple math calculations, and posts the answer to the channel (or user if in a private message).  Examples:

	!calc 45 + 5
	!calc (374634 * 34) / 500.1
	!calc 2 ** 8

### CONVERT

	CONVERT value units to units

This command converts numerical values between various units, such as temperature, weight and volume.  It posts the answer to the channel (or user if in a private message).  For example, you could type "!convert 45 lbs to kg" to convert pounds to kilograms, which would output 20.41165665 kg.  Examples:

	!convert 100 lbs to kg
	!convert 25 C to F
	!convert 5 mm to in
	!convert 1 gallon to cm^3
	!convert 4500 rpm to hz

### HASH

	HASH
	HASH string

This command computes an MD5 digest (hash) given a source string, or creates a random one if nothing is provided.  The output is 32-characters in length, lower-case, and hexadecimal encoded.

### PICK

	PICK

This command picks a random user from the current channel.  All nicks that end in "bot" or "serv" are excluded, as well as the bot itself (even if its name doesn't end in "bot").  The idea is to pick humans only.  The chosen user's nickname is emitted to the channel.  Uses an ultra-random number generator.

### RAND

	RAND
	RAND max
	RAND min - max

This command picks a random number, and emits the result.  Without any parameters, it picks a floating point decimal between 0.0 and 1.0.  With one number specified, it is treated as the maximum, and picks a number between 0 and it.  With two numbers specified, they are treated as a range.  Will round down to nearest integer if only integers are provided, otherwise it will use floats.  Uses an ultra-random number generator.

### ROLL

	ROLL dice
	ROLL dice +/- modifier

This command rolls dice for use in RPGs like Dungeons & Dragons.  It can roll any number of any-sided die, plus or minus a modifier.  The syntax for the dice is (NUM)d(SIDES), and the optional modifier is simply +/-(NUMBER).  Uses an ultra-random number generator.  Examples:

	!roll 1d6
	!roll 2d20
	!roll 1d100 +20

## Clock Group

### ALARM

	ALARM SET date/time
	ALARM SET date/time description
	ALARM LIST
	ALARM DELETE index

Use ALARM SET to set an alarm for any future date/time.  The bot should figure out your formatting.  Something as simple as "!alarm set 8:30" would work, as well as "!alarm set sunday january 25 6pm repeat call nancy".  Include the word "repeat" for a repeating alarm (otherwise it is one time only), and an optional description.
Enter "!alarm list" to list all the current alarms, and "!alarm delete 1" to delete the first one in the list.  The alarm will sound in the channel in which it was set.
Examples:

	!alarm set 9:45
	!alarm set 4:30 pm Walk the Dog
	!alarm set saturday 11 am repeat Watch Podcast

### COUNTDOWN

	COUNTDOWN TO time
	COUNTDOWN TO date/time description
	COUNTDOWN TO CALENDAR
	COUNTDOWN STOP

This command sets a countdown to a specific point in time.  Specify the destination date and/or time, or use the keyword "calendar" to count down to the next event on a Google Calendar attached to the channel.  Examples: "!countdown to 7:30", and "!countdown to calendar".  The bot emits progress reports in ever-increasing frequency as the target time approaches.  Use "!countdown stop" to cancel an active timer.  Only one timer may be active per channel.  Examples:

	!countdown to 9:30
	!countdown to midnight
	!countdown to sunday 4:30 pm
	!countdown to calendar

### TIME

	TIME
	TIME timezone

This command prints the current bot server date and time, in the local timezone of the user, if known (i.e. see !help location).  Examples:

	!time
	!time Eastern
	!time GMT

### TIMER

	TIMER MM::SS
	TIMER HH::MM::SS
	TIMER STOP

This command sets a countdown timer, given a duration specified in MM::SS, HH::MM::SS or human time, such as "5 minutes".  The bot emits progress reports in ever-increasing frequency as the target time approaches.  Use "!timer stop" to cancel an active timer.  Only one timer may be active per channel.  Examples:

	!timer 5:00
	!timer 1:00:00
	!timer 45 minutes
	!timer 12 hours

### TIMEZONE

	TIMEZONE zone

Set your personal timezone for future date/time queries.  It will always be remembered for you, so you only have to enter it once.  This affects bot commands such as !time, !alarm and !countdown.  You can use any of the following formats:

	!timezone Pacific
	!timezone Eastern
	!timezone America/Los_Angeles
	!timezone GMT-0800

## Earthquake Group

### QUAKES

	QUAKES on
	QUAKES off
	QUAKES status
	QUAKE
This command can enable or disable live earthquake monitoring (data provided by USGS).  The bot can emit earthquake reports into the current channel, within 60 seconds of the event happening.  Type "!quakes on" to enable live monitoring, "!quakes off" to disable it, and "!quakes status" to get the current status.  You can also type "!quake" to emit the most recent quake reported in the last 24 hours.
The USGS provides five different earthquake feeds, which vary on their minimum magnitude.  To set which feed to pull from, use this command:

	!config set Earthquake/FeedID significant

Acceptable values for FeedID are "significant", "4.5", "2.5", "1.0" or "all".

## FAQ Group

### FAQ

	FAQ command answer
	FAQ list
	FAQ delete NUMBER

This registers a custom FAQ command and associates some text with it.  Then, users can recall the FAQ answer by entering the custom command just like any other bot command.  You can also use "!faq list" to get a list of all the FAQ commands for the current channel, and "!faq delete NUMBER" to delete them.  Examples:

	!faq myserver Welcome to my server!  Please read the rules at http://myserver.com/rules/
	!myserver
	!faq list
	!faq delete 1

## Google Calendar Group

### CALENDAR

	CALENDAR SET your-google-cal-id
	CALENDAR REFRESH
	CALENDAR CURRENT
	CALENDAR NEXT
	CALENDAR DELETE

These commands allow you to attach a Google Calendar to the current #channel, so you can emit the current and next events anytime you want.  To find your Calendar ID, open your calendar in Google, make sure it is public, edit settings, then grab the ID in the "Calendar Address" section which should look like this: "(Calendar ID: iu9de9ell3bhagnk1con4052q0@group.calendar.google.com)".
The CALENDAR command can be abbreviated to just "CAL" if you want, i.e. "!cal refresh".

### CURRENT

	CURRENT
This emits the current calendar event to the channel, including its title and the time it started (uses timezone from calendar).

### NEXT

	NEXT
This emits the next upcoming calendar event to the channel, including its title and starting time (uses timezone from calendar).  Will also include the starting date if it is after today.

## Hello Bye Group

### BYE

	BYE goodbye-text
This sets an automatic "goodbye" that the bot will speak in each channel you leave (or all channels if you drop off IRC). Omit goodbye text to disable.

### HELLO

	HELLO greeting-text
This sets an auto-greeting of your choice, which the bot will remember. When you join a channel that the bot is in, it will speak your custom greeting.  Omit greeting text to disable.

## Help Group

### HELP

	HELP
	HELP command
Shows general help, or if a command is specified, shows help for that particular command.

## Insult Group

### INSULT

	INSULT nickname
	INSULT nickname adjective
	INSULT nickname adjective noun.

Generates a random insult and throws it at the target user.  You may specify replacement adjectives and/or a replacement noun if you like.  Specify which is which by adding punctuation to the noun only.
The insult database was borrowed and modified from the Perl Acme-Scurvy-Whoreson-BilgeRat-Backend-insultserver module: http://search.cpan.org/dist/Acme-Scurvy-Whoreson-BilgeRat-Backend-insultserver/

## Last Group

### LAST

	LAST nickname
This reports when the user was last seen in the channel, and what he/she last said.

## Net Group

### HEAD

	HEAD url

This command analyzes a given URL, and reports back its size, web server software, and any other information it has.
Command aliases: !whead, !http, !sniff, !url

### HOST

	HOST hostname

This command attempts to resolve a given hostname to IP address, or IP to hostname, using local DNS.
Command alias: !dns

### PING

	PING hostname
This command pings a given hostname or IP address, and reports the round trip packet time.

### TCP

	TCP hostname port

This command attempts a TCP socket connection on the given hostname/IP and port.  It returns if the operation was successful or not.
Command aliases: !connect, !telnet

## Points Group

### AWARD

	AWARD nickname points

This gives the target user the specified amount of "points".  Points are an arbitrary score rating which can be used for whatever you want.  The amount of points must be an integer.  Examples:

	!award eric 50
	!award nancy 10

### DEDUCT

	DEDUCT nickname points

This is the opposite of award, meaning it takes points away from the user.  If the user's score hits zero (or below) they are removed from the score list.  Examples:

	!deduct eric 50
	!deduct nancy 10

### POINTS

	POINTS AWARD - Award points to a user.
	POINTS DEDUCT - Deduct points from a user.
	POINTS SCORES - Show the top scores or clears the list.

Use these commands to manage a "points" system for your users.  Give special users points for rewards that you invent.  You can reward or deduct points, and see the current "scores" of the top users.  You can optionally omit the POINTS command and just type the sub-commmands directly.  See help on the individual sub-commands for more details, e.g. HELP AWARD or HELP SCORES.

### SCORES

	SCORES
	SCORES 20
	SCORES clear

This shows you the top scoring users with the most points.  It defaults to showing the top 10, but you can include a different number to show the top N users.  To clear ALL the scores from all users, enter "!scores clear".

## Poll Group

### POLL

	POLL open MY TITLE
	POLL open MY TITLE (ITEM1, ITEM2, ITEM3)
	POLL status
	POLL close
	POLL results
	POLL history

This command manages polls.  Use the "!poll open ..." command to start a new poll, but specify the poll title after the command, e.g. "!poll open What's your favorite food?".  Type "!poll close" to close the poll, and "!poll results" to get the voting results.  To see historical polls, use "!poll history".  If you want to limit the items people can vote for, include them as a comma-separated list in parenthesis.  Examples:

	!poll open What's your favorite OS?
	!poll open What game should we play? (Minecraft, FTB, Pong)
	!poll close
	!poll results

### VOTE

	VOTE (your vote)

This command casts your vote in the current open poll.  Just enter the desired value after the command, e.g. "!vote pizza".  Votes are matched case-insensitively against previous votes.  So if someone votes for "pizza" and someone else votes for "PIZZA", they are treated as the same value.

## Topic Group

### TOPIC

	TOPIC - Set the channel topic column.
	TOWNER - Set the channel topic "owner" column (your name).
	TVERB - Set the channel topic "verb" column (i.e. "is").
	TSTATUS - Set the channel topic "status" column (i.e. "Away").
	TSTATIC - Set the channel topic "static" column (i.e. your website URL).
	TDIVIDER - Set the divider string which separates the topic columns, defaults to a pipe (|).
	TREFRESH - Refresh the channel topic, in case some Op changed it manually.
	TRESET - Reset (clear) the topic to a blank string.
	TON - Shortcut for !tstatus Online
	TOFF - Shortcut for !tstatus Offline

These commands control the channel topic using a set of named "columns" and a divider.  It is based on an original design by TMFKsoft and also used in the popular Techie-Bot.  It produces topics like the following: "Minecraft Chat | Eric is Online | http://mysever.com".  That is made of up 5 different columns, a topic (Minecraft Chat), an owner (Eric), a verb (is), a status (Online), and a static string (http://myserver.com).  You can set each column separately without affecting the others:

	!topic Minecraft Chat
	!towner Eric
	!tverb is
	!tstatus Away
	!tstatic http://mywebsite.com

## Twitter Group

### FOLLOW

	FOLLOW @username

Starts following @username's tweets on Twitter, and automatically echos them into the current channel.  Will omit @replies and RTs by the user.  Please note that due to Twitter API throttling, the bot can only check one per user's timeline once per minute, so if the bot is following 2 people, it may take up to 2 minutes to see new tweets from either of them.

### FOLLOWING

	FOLLOWING

List all users we are currently following on Twitter, and in which channels.

### RT

	RT @username

Retweet the last tweet of the specified Twitter username.  Will omit @replies and RTs by the user.

### TWITTER

	TWITTER RT - Retweet the last tweet of any Twitter username into the current channel.
	TWITTER FOLLOW - Start following a Twitter username in the current channel.
	TWITTER UNFOLLOW - Stop following a Twitter username in the current channel.
	TWITTER FOLLOWING - List all users we are current following on Twitter.
	TWITTER RELOAD - Reload the Twitter Plugin (reconnect to the Twitter API).

Use these commands to follow people on twitter, manage your follow list, or retweet the latest tweet by any Twitter user.  You can optionally omit the TWITTER command and just type the sub-commmands directly (except for RELOAD).  See help on the individual sub-commands for more details, e.g. HELP RT or HELP FOLLOW.

To set up the Twitter Plugin for the first time, you will have to register for an API key at dev.twitter.com.  This is a free developer API so the bot can establish a connection on your account's behalf, to read tweets using the officialy supported Twitter API v1.1.  Go to https://dev.twitter.com/ to get started.
To register the bot, go to https://dev.twitter.com/apps and click "Create a new application".  Fill out the form, naming the application whatever you want.  The bot only requires "Read Only" access, and you can leave the "Callback URL" blank.
When finished, click "Create your Twitter application".  At this point you should be given 4 different alphanumeric keys, a "Consumer key", "Consumer secret", "Access token" and "Access token secret".  Teach all four of these to the bot like this:

	!config set Twitter/ConsumerKey YOUR_CONSUMER_KEY_HERE
	!config set Twitter/ConsumerSecret YOUR_CONSUMER_SECRET_HERE
	!config set Twitter/AccessToken YOUR_ACCESS_TOKEN_HERE
	!config set Twitter/AccessTokenSecret YOUR_ACCESS_TOKEN_SECRET_HERE

At this point the Twitter Plugin should be ready to use, and the API keys will be saved in case the bot restarts.  Test it by trying to retweet your last tweet into chat: "!rt @YOUR_TWITTER_NAME".

### UNFOLLOW

	UNFOLLOW @username

Stop following @username's tweets in the current channel.

## Weather Group

### FORECAST

	FORECAST location

Get a 5-day forecast for the specified location, which can be any 5-digit US ZIP code, or any city and country separated by spaces.  For example, 'forecast guelph canada' or 'forecast toronto canada'.  Countries needs to be spelled out.
See "!help weather" for details on setting up your API key for WeatherUnderground.com (it's free).

### LOCATION

	LOCATION city state country
	LOCATION zipcode

Set your location for future weather and date/time queries, which the bot remembers.  This also looks up your time zone based on your location, and stores that for displaying and calculating dates and times for you.
See "!help weather" for details on setting up your API key for WeatherUnderground.com (used for the location service -- it's free).

### WEATHER

	WEATHER location

Get current weather conditions.  Specify any 5-digit US ZIP code, or any city and country separated by spaces.  For example, 'weather guelph canada' or 'weather toronto canada'.  Countries need to be spelled out.

To get weather for countries outside the US, you will need to register for a free API Key at: http://www.wunderground.com/weather/api/
After signing up, copy your API key and paste it into this command:

	!config set Weather/APIKey YOUR_API_KEY_HERE

At this point the Weather Plugin should be ready to use.  Test it out by checking your local weather: "!weather london england".

## Web Search Group

### DEFINE

	DEFINE term
This uses the Wikipedia API to locate a suitable definition for a term.  The result is emitted to the current channel.  If a definition cannot be found, the bot also tries DictionaryAPI.com (Merriam-Webster), which requires a free API key.  Sign up at http://www.dictionaryapi.com/ and then configure your API key with this command:

	!config set WebSearch/DictAPIKey YOUR_API_KEY_HERE

Note that this is optional, and the DEFINE command works just fine with Wikipedia for most terms.  The DictionaryAPI.com is mainly used as a fallback, if the Wikipedia API fails or it doesn't define a particular term.

### GOOGLE

	GOOGLE search-query
	GOOGLE nickname
This uses the Google Search API to search for a query, and returns the first result.  If a username is specified, the last thing the user said is used as the query.  The result is emitted to the current channel.

### IMAGE

	IMAGE search-query
	IMAGE nickname
This uses the Google Image Search API to search for an image given a text string, and returns a direct URL to the first result.  If a username is specified, the last thing the user said is used as the query.  The result is emitted to the current channel.  If you repeat the same query multiple times, it will cycle through the first 4 results.

### SPELL

	SPELL word
This command uses the free API provided by DictionaryAPI.com (Merriam-Webster) to check the spelling of a word.  If the word cannot be found in the dictionary, spelling suggestions are provided.  Please note that this API requires a free API key.  Sign up at http://www.dictionaryapi.com/ and then configure your API key with this command: 

	!config set WebSearch/DictAPIKey YOUR_API_KEY_HERE

### STOCK

	STOCK symbol
This uses the Yahoo Finance API to grab a stock quote for the given symbol.  It reports the current price and change.  Example: !stock GOOG

### URBAN

	URBAN term
This uses the Urban Dictionary API to locate a suitable definition for a term.  The result is emitted to the current channel.  Beware: Urban Dictionary can be very NSFW.  Use this at your own risk.  Remember, you can restrict access for any command to be owner only: !access set urban owner

## Copyright and Legal

SimpleBot is copyright (c) 2013 - 2014 by Joseph Huckaby and PixlCore.com.  It is released under the MIT License (see below).

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
