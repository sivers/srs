create type public.state as enum ('new', 'learning', 'review', 'relearning');
create type public.rating as enum ('again', 'hard', 'good', 'easy');

create table public.cards (
	id integer primary key generated by default as identity,
	deck varchar(10) not null default 'in',
	front text not null unique,         -- content (question)
	back text not null,                 -- content (answer)
	state state not null default 'new', -- state of the card (new, learning, review, relearning)
	due timestamptz(0) not null default now(), -- datetime when the card is next due for review
	scheduled_days integer not null default 0, -- days until card is due (interval until next scheduled)
	elapsed_days integer not null default 0, -- days since card was last reviewed
	last_review timestamptz(0),         -- most recent review date/time
	reps integer not null default 0,    -- times the card has been reviewed
	lapses integer not null default 0,  -- times the card was forgotten or remembered incorrectly
	stability numeric not null default 0,  -- how well the information is retained
	difficulty numeric not null default 0  -- inherent difficulty of the card content
);
create index cardeck on cards(deck);
create index cardue on cards(due);

-- all functions in schema srs, so that you can ...
-- drop schema srs cascade; create schema srs;
-- ... to replace all functions, but not lose table data.
create schema srs;
set search_path = srs, public;

