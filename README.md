# Open Spaced Repetition in PostgreSQL functions


## origin

[Free Spaced Repetition Scheduler (v5)](https://github.com/open-spaced-repetition)



## this PostgreSQL version

Written by [Derek Sivers](https://sive.rs/) in September 2024.
I'm happy to discuss it, so [email me](https://sive.rs/contact) if you want, especially if you find errors.
Take it and adapt it for you or others to use, since this implementation is meant for my own personal use, suited for just me.
I gave my parts the "unlicense" so you don't need to credit me.



## install

```
cd db/
createuser srs
createdb -O srs srs
psql -U srs -d srs -f tables.sql
sh reload-functions.sh
```



## API (use only this)

| API function | parameters | purpose |
|--------------|-------|---------|
| **add** | deck, front, back | create a new card with this content |
| **edit** | cards.id, deck, front, back | update this card's content |
| **decks** |  | list how many cards due in each deck |
| **next** | deck | get next due card from this deck |
| **review** | cards.id, rating | after quizzing, rate card as again, hard, good, or easy |

Every API function returns "ok" boolean and "js" JSON.
If "ok" is false, "js" will be {"error": "explanation"}



## usage

```sql
select add('pets', 'My first dog?', 'Charlie');
select add('pets', 'My last dog?', 'Snoopy');
select add('places', 'Capital of Azerbaijan?', 'Bakoo');

select edit(3, 'places', 'Capital of Azerbaijan?', 'Baku');

select decks();

select next('pets');
select review(1, 'hard');

select next('pets');
select review(2, 'easy');
```

Front and Back content is interpreted as HTML, so put media files into public/ directory then use HTML to present them:

```sql
select add('places',
  'How to say this place? <img src="paris.jpg">',
  'Paris <audio src="paris.mp3"></audio>');
```



## functions.sql (behind the scenes)

The Free Spaced Repetition Scheduler is in functions.sql,
copied from [algorithm.ts](https://github.com/open-spaced-repetition/ts-fsrs/blob/main/src/fsrs/algorithm.ts)
and [basic\_scheduler.ts](https://github.com/open-spaced-repetition/ts-fsrs/blob/main/src/fsrs/impl/basic_scheduler.ts)

Thank you to [the wonderful people](https://github.com/orgs/open-spaced-repetition/people) who work so hard on this.



## omitted

I don't need fuzzing, undo/rollback, log analysis optimization, or differentiation between basic versus long term scheduling, so I didn't add those.
I've used Anki every day for 15+ years, so I know what I do and don't need.
Simplification was my mission.



## web, using Ruby

```
gem install pg
gem install sinatra
ruby web.rb
```

HTML in the views/ directory.

/ webroot in public/ is for cards' media files.



## TODO

1. autoplay audio/video when viewing card front
2. when flipped, stop front audio/video, start back audio/video
3. test against FSRS to make sure I got scheduler right

