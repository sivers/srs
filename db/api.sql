-- API FUNCTIONS: JUST CALL THESE
-- decks()	| 

create function srs.decks(
	out ok boolean, out js json) as $$
begin
	ok = true;
	js = coalesce((select json_agg(r) from (
		select deck, count(id)
		from cards
		where due < now()
		or due is null
		group by deck
		order by deck
	) r), '[]');
end;
$$ language plpgsql;


create function srs.add(_deck text, _front text, _back text,
	out ok boolean, out js json) as $$
declare
	err text;
begin
	ok = true;
	with nu as (
		insert into cards (deck, front, back)
		values ($1, $2, $3)
		returning id
	) select row_to_json(nu.*) into js from nu;
exception
	when others then get stacked diagnostics err = message_text;
	js = json_build_object('error', err);
	ok = false;
end;
$$ language plpgsql;


create function srs.next(_deck text,
	out ok boolean, out js json) as $$
begin
	ok = true;
	js = row_to_json(r) from (
		select id, front, back
		from cards
		where deck = $1
		and due < now()
		or due is null
		order by due nulls first limit 1
	) r;
	if js is null then
		ok = false;
		js = json_build_object('error', 'not found');
	end if;
end;
$$ language plpgsql;


create function srs.edit(_id integer, _deck text, _front text, _back text,
	out ok boolean, out js json) as $$
declare
	err text;
begin
	update cards
	set deck = $2, front = $3, back = $4
	where id = $1;
	ok = true;
	js = '{}';
exception
	when others then get stacked diagnostics err = message_text;
	js = json_build_object('error', err);
	ok = false;
end;
$$ language plpgsql;


-- rate as 'again', 'hard', 'good', or 'easy'
-- returns deck of this card to be used in next(deck)
create function srs.review(_cardid integer, rating,
	out ok boolean, out js json) as $$
declare
	err text;
begin
	perform card_review($1, $2);
	ok = true;
	js = row_to_json(r) from (
		select deck from cards where id = $1
	) r;
exception
	when others then get stacked diagnostics err = message_text;
	js = json_build_object('error', err);
	ok = false;
end;
$$ language plpgsql;

