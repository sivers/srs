-- PRIVATE FUNCTIONS, all to serve the final one: card_review
-- Don't use these.  They use each other.  Instead, see api.sql

-- DECAY: CONSTANT: set to -0.5
create function decay() returns numeric as $$
	select -0.5;
$$ language sql immutable;

-- FACTOR: CONSTANT: set to 19/81 (0.23456790123456790123)
create function factor() returns numeric as $$
	select 19::numeric / 81;
$$ language sql immutable;

-- WEIGHTS: w(0) returns first, w(18) returns last
create function w(int) returns numeric as $$
	select (array[0.4072, 1.1829, 3.1262, 15.4722, 7.2102, 0.5316,
		1.0651, 0.0234, 1.616, 0.1544, 1.0824, 1.9813, 0.0953,
		0.2975, 2.2042, 0.2407, 2.9466, 0.5034, 0.6567])[$1 + 1];
-- PostgreSQL array indices start at 1, so retrieve by adding 1 to param
$$ language sql immutable;

-- CONSTANT / default
create function request_retention() returns numeric as $$
	select 0.9;
$$ language sql immutable;

-- CONSTANT / default
create function maximum_interval() returns integer as $$
	select 36500;
$$ language sql immutable;

-- convert grade/rating ('again','hard','good','easy') into integer (1,2,3,4)
create function gradenum(g rating) returns integer as $$
	select array_position(enum_range(null::rating), $1::rating);
$$ language sql immutable;

-- bind/"clamp" value $1 to be $2 minimum, $3 maximum, so $2 <= $1 <= $3
-- returns updated $1 within these limits
create function clamp(numeric, numeric, numeric) returns numeric as $$
	select least(greatest($1, $2), $3);
$$ language sql immutable;

-- https://github.com/open-spaced-repetition/fsrs4anki/wiki/The-Algorithm
-- LaTeX formula:
-- I(r,s) = (r^{\frac{1}{DECAY}} - 1) / FACTOR \times s
-- not multiplied by s here, but that's done where it's called
-- param request_retention 0<request_retention<=1,Requested retention rate
create function calculate_interval_modifier(r numeric) returns numeric as $$
	select (power(r, 1 / decay()) - 1) / factor();
$$ language sql immutable;

-- LaTeX formula:
-- S_0(G) = w_{G-1}
-- S_0 = \max \lbrace S_0,0.1\rbrace
-- param g Grade (rating) [1=again,2=hard,3=good,4=easy]
-- return Stability (interval when R=90%)
create function init_stability(g rating) returns numeric as $$
	select greatest(w(gradenum(g) - 1), 0.1);
$$ language sql immutable;

-- original had 3 params, but 2nd and 3rd were only for fuzzing, I only need stability
-- param: s - Stability (interval when R=90%)
create function next_interval(s numeric) returns integer as $$
	select least(greatest(1,
		round(s * calculate_interval_modifier(request_retention()))
	), maximum_interval());
$$ language sql immutable;

-- LaTeX formula:
-- w_7 \cdot \text{init} +(1 - w_7) \cdot \text{current}
-- param init $$w_2 : D_0(3) = w_2 + (R-2) \cdot w_3= w_2$$
-- param current $$D - w_6 \cdot (R - 2)$$
-- return difficulty
create function mean_reversion(init numeric, curr numeric) returns numeric as $$
	select w(7) * init + (1 - w(7)) * curr;
$$ language sql immutable;

-- LaTeX formula:
-- \min \lbrace \max \lbrace D_0,1 \rbrace,10\rbrace
-- @param {number} difficulty $$D \in [1,10]$$
create function constrain_difficulty(d numeric) returns numeric as $$
	select least(greatest(d, 1), 10);
$$ language sql immutable;

-- LaTeX formula:
-- D_0(G) = w_4 - e^{(G-1) \cdot w_5} + 1
-- D_0 = \min \lbrace \max \lbrace D_0(G),1 \rbrace,10 \rbrace
-- where the D_0(1)=w_4 when the first rating is good.
-- param g Grade (rating) [1=again,2=hard,3=good,4=easy]
-- return {number} Difficulty $$D \in [1,10]$$
create function init_difficulty(g rating) returns numeric as $$
	select constrain_difficulty(w(4) - exp((gradenum(g) - 1) * w(5)) + 1);
$$ language sql immutable;

-- LaTeX formula:
-- \text{next}_d = D - w_6 \cdot (g - 3)
-- D^\prime(D,R) = w_7 \cdot D_0(4) +(1 - w_7) \cdot \text{next}_d
-- param d Difficulty $$D \in [1,10]$$
-- param g Grade (rating) [1=again,2=hard,3=good,4=easy]
-- return {number} $$\text{next}_D$$
create function next_difficulty(d numeric, g rating) returns numeric as $$
	select constrain_difficulty(
	  mean_reversion(init_difficulty('easy'), d - w(6) * (gradenum(g) - 3))
	);
$$ language sql immutable;

-- LaTeX formula:
-- S^\prime_r(D,S,R,G) = S\cdot(e^{w_8}\cdot (11-D)\cdot S^{-w_9}\cdot(e^{w_{10}\cdot(1-R)}-1)\cdot w_{15}(\text{if} G=2) \cdot w_{16}(\text{if} G=4)+1)
-- param d Difficulty D \in [1,10]
-- param s Stability (interval when R=90%)
-- param r Retrievability (probability of recall)
-- param g Grade (rating) [1=again,2=hard,3=good,4=easy]
-- @return {number} S^\prime_r new stability after recall
create function next_recall_stability(d numeric, s numeric, r numeric, g rating) returns numeric as $$
	with vars as (select
		case when 'hard' = g then w(15) else 1 end as hard_penalty,
		case when 'easy' = g then w(16) else 1 end as easy_bound
	)
	select clamp(
		s * (
			1 + exp(w(8)) * (11 - d) * power(s, -w(9)) *
			(exp((1 - r) * w(10)) - 1) *
			hard_penalty * easy_bound
		),
	0.01, maximum_interval()) from vars;
$$ language sql immutable;

-- LaTeX formula:
-- S^\prime_f(D,S,R) = w_{11}\cdot D^{-w_{12}}\cdot ((S+1)^{w_{13}}-1) \cdot e^{w_{14}\cdot(1-R)}
-- param d Difficulty D \in [1,10]
-- param s Stability (interval when R=90%)
-- param r Retrievability (probability of recall)
-- @return {number} S^\prime_f new stability after forgetting
create function next_forget_stability(d numeric, s numeric, r numeric) returns numeric as $$
	select clamp(
		w(11) * power(d, -w(12)) *
		(power(s + 1, w(13)) - 1) *
		exp((1 - r) * w(14)),
	0.01, maximum_interval());
$$ language sql immutable;

-- LaTeX formula:
-- S^\prime_s(S,G) = S \cdot e^{w_{17} \cdot (G-3+w_{18})}
-- param s Stability (interval when R=90%)
-- param g Grade (rating) [1=again,2=hard,3=good,4=easy]
-- @return {number} S^\prime_f new stability after forgetting
create function next_short_term_stability(s numeric, g rating) returns numeric as $$
	select clamp(
		s * exp(w(17) * (gradenum(g) - 3 + w(18))),
	0.01, maximum_interval());
$$ language sql immutable;

-- LaTeX formula:
-- R(t,S) = (1 + \text{FACTOR} \times \frac{t}{9 \cdot S})^{\text{DECAY}}
-- param elapsed_days since the last review
-- param s Stability (interval when R=90%)
-- @return {number} r Retrievability (probability of recall)
create function forgetting_curve(days integer, s numeric) returns numeric as $$
	select power(1 + (factor() * days) / s, decay());
$$ language sql immutable;


-- This could be in API, but it relies so much on algorithm features, so putting it here.
-- INPUT cards.id and rating ('again', 'hard', 'good', 'easy')
-- update almost everything about it (except id/deck/front/back):
-- update state, due, scheduled_days, stability, difficulty
-- update reps, lapses, elapsed_days, last_review
create or replace function card_review(card_id int, grade rating, out nu cards) as $$
declare
	previous cards; -- as it is now, before updating
	nu cards; -- as is will be when updated at function end
begin
	select * into previous from cards where id = $1;

	-- UPDATE: reps, lapses, last_review, elapsed_days
	-- (since these don't depend on previous.state)
	nu.reps = previous.reps + 1;
	if grade = 'again' then
		nu.lapses = previous.lapses + 1;
	else
		nu.lapses = previous.lapses;
	end if;
	if previous.last_review is null then
		nu.elapsed_days = 0;
	else
		nu.elapsed_days = extract(day from (now() - previous.last_review));
	end if;
	nu.last_review = now();

	-- UPDATE: stability, difficulty, state, scheduled_days, due
	-- These depend on previous.state and grade/rating: case-within-case
	-- This approach has some duplication but much clarity
	case previous.state
	when 'new' then
		nu.difficulty = init_difficulty(grade);
		nu.stability = init_stability(grade);
		case grade
		when 'again' then
			nu.state = 'learning';
			nu.scheduled_days = 0;
			nu.due = now() + interval '1 minute';
		when 'hard' then
			nu.state = 'learning';
			nu.scheduled_days = 0;
			nu.due = now() + interval '5 minutes';
		when 'good' then
			nu.state = 'learning';
			nu.scheduled_days = 0;
			nu.due = now() + interval '10 minutes';
		when 'easy' then
			nu.state = 'review';
			nu.scheduled_days = next_interval(nu.stability);
			nu.due = now() + (nu.scheduled_days || ' days')::interval;
		end case;
	when 'learning', 'relearning' then
		nu.difficulty = next_difficulty(previous.difficulty, grade);
		nu.stability = next_short_term_stability(previous.stability, grade);
		case grade
		when 'again' then
			nu.state = previous.state;
			nu.scheduled_days = 0;
			nu.due = now() + interval '5 minutes';
		when 'hard' then
			nu.state = previous.state;
			nu.scheduled_days = 0;
			nu.due = now() + interval '10 minutes';
		when 'good' then
			nu.state = 'review';
			nu.scheduled_days = next_interval(nu.stability);
			nu.due = now() + (nu.scheduled_days || ' days')::interval;
		when 'easy' then
			nu.state = 'review';
			nu.scheduled_days = greatest(next_interval(nu.stability),
				1 + next_interval(next_short_term_stability(previous.stability, 'good'))
			);
			nu.due = now() + (nu.scheduled_days || ' days')::interval;
		end case;
	when 'review' then
		nu.difficulty = next_difficulty(previous.difficulty, grade);
		if grade = 'again' then
			nu.stability = next_forget_stability(
				previous.difficulty,
				previous.stability,
				forgetting_curve(previous.elapsed_days, previous.stability));
		else
			nu.stability = next_recall_stability(
				previous.difficulty,
				previous.stability,
				forgetting_curve(previous.elapsed_days, previous.stability),
				grade);
		end if;
		case grade
		when 'again' then
			nu.state = 'relearning';
			nu.scheduled_days = 0;
			nu.due = now() + interval '5 minutes';
		when 'hard' then
			nu.state = previous.state;
			nu.scheduled_days = next_interval(nu.stability);
			nu.due = now() + (nu.scheduled_days || ' days')::interval;
		when 'good' then
			nu.state = previous.state;
			nu.scheduled_days = greatest(
				next_interval(nu.stability),
				1 + next_recall_stability(
					previous.difficulty,
					previous.stability,
					forgetting_curve(previous.elapsed_days, previous.stability),
					'hard'
				)
			);
			nu.due = now() + (nu.scheduled_days || ' days')::interval;
		when 'easy' then
			nu.state = previous.state;
			nu.scheduled_days = greatest(
				next_interval(nu.stability),
				1 + next_recall_stability(
					previous.difficulty,
					previous.stability,
					forgetting_curve(previous.elapsed_days, previous.stability),
					'good'
				)
			);
			nu.due = now() + (nu.scheduled_days || ' days')::interval;
		end case; 
	end case;

	-- UPDATE WITH NEW VALUES:
	update cards set
	reps = nu.reps,
	lapses = nu.lapses,
	last_review = nu.last_review,
	elapsed_days = nu.elapsed_days,
	stability = nu.stability,
	difficulty = nu.difficulty,
	state = nu.state,
	scheduled_days = nu.scheduled_days,
	due = nu.due
	where id = $1;
end;
$$ language plpgsql;

