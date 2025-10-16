-- {"query": "157.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 2703} 
with recent_qs as (
  select p.*
  from posts p
  where p.posttypeid = 1
    and p.creationdate >= now() - interval '365 days'
    and (p.tags is not null and length(p.tags) > 2)
),
tag_expanded as (
  select
    q.id as question_id,
    trim(t) as tag
  from recent_qs q,
  lateral (
    select unnest(string_to_array(substring(q.tags,2,length(q.tags)-2), '><')) as t
  ) s
),
answers as (
  select a.*
  from posts a
  where a.posttypeid = 2
    and a.creationdate >= now() - interval '366 days'
),
vote_summary as (
  select
    v.postid,
    sum(case when v.votetypeid = 2 then 1 else 0 end) filter (where v.votetypeid is not null) as upvotes,
    sum(case when v.votetypeid = 3 then 1 else 0 end) filter (where v.votetypeid is not null) as downvotes,
    sum(case when v.votetypeid in (8,9) then coalesce(v.bountyamount,0) else 0 end) as bounty_total,
    count(*) as total_votes,
    count(distinct v.userid) as distinct_voters
  from votes v
  group by v.postid
),
user_badges as (
  select
    b.userid,
    count(*) filter (where b.class = 1) as gold_badges,
    count(*) filter (where b.class = 2) as silver_badges,
    count(*) filter (where b.class = 3) as bronze_badges,
    bool_or(b.tagbased::boolean) as has_tag_based
  from badges b
  group by b.userid
),
last_edits as (
  select ph.postid,
         max(ph.creationdate) as last_history_date,
         count(*) filter (where ph.posthistorytypeid in (4,5,6)) as edit_count,
         max(ph.posthistorytypeid) filter (where ph.posthistorytypeid is not null) as last_history_type
  from posthistory ph
  group by ph.postid
),
top_answerers_per_question as (
  select
    q.id as question_id,
    a.owneruserid as answerer_id,
    count(a.id) as answers_by_user,
    sum(coalesce(vs.upvotes,0) - coalesce(vs.downvotes,0)) as net_votes_on_answers,
    row_number() over (partition by q.id order by count(a.id) desc, sum(coalesce(vs.upvotes,0)-coalesce(vs.downvotes,0)) desc nulls last) as rn
  from recent_qs q
  join answers a on a.parentid = q.id
  left join vote_summary vs on vs.postid = a.id
  group by q.id, a.owneruserid
),
question_aggregates as (
  select
    q.id,
    q.title,
    q.creationdate,
    q.viewcount,
    coalesce(vs.upvotes,0) as question_upvotes,
    coalesce(vs.downvotes,0) as question_downvotes,
    coalesce(q.answercount,0) as answer_count,
    coalesce(q.favoritecount,0) as favorites,
    coalesce(le.edit_count,0) as edit_count,
    coalesce(le.last_history_type,0) as last_history_type,
    case
      when q.closeddate is not null then 'closed'
      when q.communityowneddate is not null then 'community'
      else 'open'
    end as status,
    (coalesce(vs.upvotes,0) - coalesce(vs.downvotes,0))::int as question_net_score,
    -- score density: net score normalized by age in days (avoid div by zero)
    (coalesce(vs.upvotes,0) - coalesce(vs.downvotes,0))::double precision / greatest(1, date_part('day', now() - q.creationdate)) as score_density,
    -- tag string manipulations
    substring(q.tags from 2 for greatest(0, length(q.tags)-2)) as tags_inner,
    -- presence of code-like tags by pattern
    (case when q.tags ~* '<.*(sql|postgres|performance|index).*>' then true else false end) as has_perf_tag
  from recent_qs q
  left join vote_summary vs on vs.postid = q.id
  left join last_edits le on le.postid = q.id
),
user_enrichment as (
  select
    u.id,
    u.displayname,
    u.reputation,
    u.creationdate,
    u.lastaccessdate,
    coalesce(ub.gold_badges,0) as gold,
    coalesce(ub.silver_badges,0) as silver,
    coalesce(ub.bronze_badges,0) as bronze,
    coalesce(ub.has_tag_based,false) as has_tag_badges,
    (u.reputation::double precision / greatest(1, date_part('day', now() - u.creationdate))) as rep_growth_per_day
  from users u
  left join user_badges ub on ub.userid = u.id
),
accepted_answerer as (
  select q.id as question_id, aa.owneruserid as accepted_answer_user, aa.id as accepted_answer_id
  from recent_qs q
  left join posts aa on aa.id = q.acceptedanswerid
),
combined as (
  select
    qa.*,
    ta.tag,
    ua.displayname as owner_displayname,
    ua.reputation as owner_reputation,
    ua.gold as owner_gold,
    ua.rep_growth_per_day,
    coalesce(ts.upvotes,0) as answer_upvotes_sum,
    coalesce(ts.downvotes,0) as answer_downvotes_sum,
    coalesce(tap.answerer_id, null) as top_answerer_id,
    tap.answers_by_user,
    tap.net_votes_on_answers,
    acc.accepted_answer_user,
    -- correlated subquery: median answer score for this question
    (select percentile_disc(0.5) within group (order by coalesce(vs.upvotes,0)-coalesce(vs.downvotes,0))
     from posts pa
     left join vote_summary vs on vs.postid = pa.id
     where pa.parentid = qa.id
    ) as median_answer_net_score
  from question_aggregates qa
  left join tag_expanded ta on ta.question_id = qa.id
  left join users ua on ua.id = (select owneruserid from posts p where p.id = qa.id)
  left join (
    select a.parentid as questionid,
           sum(coalesce(vs.upvotes,0)) as upvotes,
           sum(coalesce(vs.downvotes,0)) as downvotes
    from posts a
    left join vote_summary vs on vs.postid = a.id
    where a.posttypeid = 2
    group by a.parentid
  ) ts on ts.questionid = qa.id
  left join top_answerers_per_question tap on tap.question_id = qa.id and tap.rn = 1
  left join accepted_answerer acc on acc.question_id = qa.id
)
select
  c.id as question_id,
  left(coalesce(c.title,'[no title]'), 200) as title_sample,
  c.creationdate,
  c.status,
  c.tag,
  c.tags_inner,
  c.has_perf_tag,
  c.viewcount,
  c.answer_count,
  c.favorites,
  c.question_upvotes,
  c.question_downvotes,
  c.question_net_score,
  round(c.score_density::numeric,6) as score_density,
  c.median_answer_net_score,
  c.answer_upvotes_sum,
  c.answer_downvotes_sum,
  c.top_answerer_id,
  c.answers_by_user,
  c.net_votes_on_answers,
  c.accepted_answer_user,
  c.edit_count,
  c.last_history_type,
  c.owner_displayname,
  c.owner_reputation,
  c.owner_gold,
  round(c.rep_growth_per_day::numeric,6) as rep_growth_per_day,
  -- complex expression mixing NULL logic, string ops, arithmetic
  case
    when c.accepted_answer_user is not null then
      'A:' || coalesce((select displayname from users u where u.id = c.accepted_answer_user),'[deleted]')
    when c.top_answerer_id is not null then
      'T:' || coalesce((select displayname from users u where u.id = c.top_answerer_id),'[deleted]')
    else
      'None'
  end as best_answerer_hint,
  -- a synthetic "health score" computed from many components
  (greatest(0, c.question_net_score) * 2
   + coalesce(c.answer_upvotes_sum,0)
   + coalesce(c.answer_downvotes_sum,0) * -1
   + coalesce(c.favorites,0) * 3
   + (case when c.has_perf_tag then 5 else 0 end)
   - least(10, coalesce(c.edit_count,0))
   + (case when c.status = 'closed' then -20 else 0 end)
  )::int as health_score,
  -- window function ranking within each tag by health_score and recency combined
  rank() over (partition by c.tag order by (health_score::double precision + (extract(epoch from (now()-c.creationdate))/86400.0)*-0.1) desc, c.score_density desc) as tag_rank,
  dense_rank() over (order by c.health_score desc) as global_dense_rank
from combined c
where c.tag is not null
  and c.tag <> ''
order by c.tag, tag_rank
limit 100

union all

-- summary row computed via set operator like UNION ALL with aggregated metrics
select
  null::int as question_id,
  'SUMMARY: Top 100 by tag_rank' as title_sample,
  null::timestamp as creationdate,
  null::varchar as status,
  null::varchar as tag,
  null::varchar as tags_inner,
  null::boolean as has_perf_tag,
  sum(viewcount) as viewcount,
  sum(answer_count) as answer_count,
  sum(favorites) as favorites,
  sum(question_upvotes) as question_upvotes,
  sum(question_downvotes) as question_downvotes,
  sum(question_net_score) as question_net_score,
  null::numeric as score_density,
  null::numeric as median_answer_net_score,
  sum(answer_upvotes_sum) as answer_upvotes_sum,
  sum(answer_downvotes_sum) as answer_downvotes_sum,
  null::int as top_answerer_id,
  null::int as answers_by_user,
  null::int as net_votes_on_answers,
  null::int as accepted_answer_user,
  null::int as edit_count,
  null::smallint as last_history_type,
  null::varchar as owner_displayname,
  avg(owner_reputation) as owner_reputation,
  sum(owner_gold) as owner_gold,
  null::numeric as rep_growth_per_day,
  null::varchar as best_answerer_hint,
  sum(health_score) as health_score,
  null::int as tag_rank,
  null::int as global_dense_rank
from (
  select *
  from (
    select c.*
    from combined c
    where c.tag is not null and c.tag <> ''
    order by c.tag, rank() over (partition by c.tag order by ( (coalesce((coalesce(c.question_net_score,0))*2,0) + coalesce(c.answer_upvotes_sum,0) + coalesce(c.favorites,0)*3 ) ) desc)
    limit 100
  ) s
) t;