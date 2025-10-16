-- {"query": "7068.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2344} 
with
-- recent activity per user with weighted recency decay
user_activity as (
  select
    u.id as user_id,
    u.displayname,
    coalesce(sum(
      case
        when p.posttypeid = 1 then 3.0   -- question
        when p.posttypeid = 2 then 2.0   -- answer
        else 0.5
      end * greatest(0.0, 1.0 - extract(epoch from (now() - coalesce(p.lastactivitydate,p.creationdate))) / (86400.0 * 180))) , 0.0) as activity_score,
    count(distinct p.id) filter (where p.id is not null) as posts_count,
    coalesce(sum(vote_up.count_up),0) as upvote_received,
    coalesce(sum(vote_down.count_down),0) as downvote_received
  from users u
  left join posts p on p.owneruserid = u.id
  left join lateral (
    select sum(case when v.votetypeid = 2 then 1 else 0 end) as count_up,
           sum(case when v.votetypeid = 3 then 1 else 0 end) as count_down
    from votes v
    where v.postid = p.id
  ) vote_up on true
  left join lateral (
    select 0 -- placeholder to keep joins symmetric (will be aggregated above)
  ) vote_down on true
  group by u.id, u.displayname
),
-- tag extraction: explode Tags string like '<tag1><tag2>'
question_tags as (
  select
    p.id as question_id,
    p.owneruserid,
    trim(t) as tag
  from posts p
  cross join lateral (
    select regexp_split_to_table(substring(p.tags from 2 for greatest(char_length(p.tags)-2,0)), '><') as t
  ) s
  where p.posttypeid = 1 and p.tags is not null and p.tags <> ''
),
-- tag popularity with last-30-day activity and growth factor
tag_stats as (
  select
    qt.tag,
    count(distinct qt.question_id) as questions_total,
    sum(case when q.creationdate >= now() - interval '30 days' then 1 else 0 end) as questions_last_30d,
    avg(p.score) filter (where p.posttypeid = 1) as avg_question_score,
    max(p.viewcount) as max_views,
    -- normalized trend: last30d / (total+1)
    (sum(case when q.creationdate >= now() - interval '30 days' then 1 else 0 end)::numeric / greatest(count(distinct qt.question_id)::numeric,1)) as recent_ratio
  from question_tags qt
  join posts p on p.id = qt.question_id
  join posts q on q.id = qt.question_id
  group by qt.tag
),
-- hot posts combining various signals, including window functions and correlated subqueries
hot_posts as (
  select
    p.id,
    p.title,
    p.owneruserid,
    p.creationdate,
    p.score,
    p.viewcount,
    p.answercount,
    p.tags,
    -- composite hotness: score*(1+sqrt(viewcount))/log(age_hours+2) + recent answers boost + favorites/upvotes
    (p.score * (1 + sqrt(coalesce(p.viewcount,0))) / nullif(log(extract(epoch from (now() - p.creationdate))/3600 + 2),0)
     + coalesce((select count(1) from posts a where a.parentid = p.id and a.creationdate >= now() - interval '7 days'),0) * 5
     + coalesce((select count(1) from votes v where v.postid = p.id and v.votetypeid = 5),0) * 3
     + coalesce((select sum(case when v.votetypeid=2 then 1 when v.votetypeid=3 then -1 else 0 end) from votes v where v.postid = p.id),0)
    ) as hotness,
    row_number() over (order by
      (p.score * (1 + sqrt(coalesce(p.viewcount,0))) / nullif(log(extract(epoch from (now() - p.creationdate))/3600 + 2),0)
       + coalesce((select count(1) from posts a where a.parentid = p.id and a.creationdate >= now() - interval '7 days'),0) * 5
       + coalesce((select sum(case when v.votetypeid=2 then 1 when v.votetypeid=3 then -1 else 0 end) from votes v where v.postid = p.id),0)
      ) desc) as rn
  from posts p
  where p.posttypeid = 1
),
-- generate pairwise linked post graph metrics (outer joins, set operators)
linked_pairs as (
  select pl.postid, pl.relatedpostid, lt.name as linktype, pl.creationdate
  from postlinks pl
  join linktypes lt on lt.id = pl.linktypeid
),
-- compute for each question: number of duplicates pointing to it, number of links from it, and earliest link
link_metrics as (
  select
    coalesce(dest.relatedpostid, src.postid) as question_id,
    sum(case when dest.linktype = 'Duplicate' then 1 else 0 end) filter (where dest.relatedpostid is not null) as duplicates_in,
    sum(case when src.linktype = 'Linked' then 1 else 0 end) filter (where src.postid is not null) as links_out,
    min(coalesce(src.creationdate, dest.creationdate)) as first_link_date
  from linked_pairs src
  full outer join linked_pairs dest on dest.relatedpostid = src.postid
  group by coalesce(dest.relatedpostid, src.postid)
),
-- user badge velocity using window and correlated subqueries
badge_velocity as (
  select
    b.userid,
    count(*) as total_badges,
    sum(case when b.class = 1 then 1 else 0 end) as gold,
    sum(case when b.class = 2 then 1 else 0 end) as silver,
    sum(case when b.class = 3 then 1 else 0 end) as bronze,
    -- badges in last year
    sum(case when b.date >= now() - interval '365 days' then 1 else 0 end) as badges_last_year,
    -- velocity: badges_last_year / (age_years + 0.1)
    (sum(case when b.date >= now() - interval '365 days' then 1 else 0 end)::numeric / greatest((extract(epoch from now() - min(u.creationdate)) / (86400*365))::numeric,0.1)) as velocity,
    row_number() over (partition by b.userid order by b.date desc) as rn
  from badges b
  join users u on u.id = b.userid
  group by b.userid
),
-- combine everything and produce heavy expressions, correlated subqueries, and set operators
benchmark_core as (
  select
    hp.id as question_id,
    hp.title,
    hp.owneruserid,
    u.displayname,
    ua.activity_score,
    ua.posts_count,
    ua.upvote_received,
    ua.downvote_received,
    hp.hotness,
    ts.tag,
    ts.questions_total,
    ts.questions_last_30d,
    ts.avg_question_score,
    ts.max_views,
    lm.duplicates_in,
    lm.links_out,
    lm.first_link_date,
    bv.total_badges,
    bv.gold, bv.silver, bv.bronze,
    bv.velocity,
    -- string manipulation: shortened title + tags snippet
    left(coalesce(hp.title,'[no title]'), 120) ||
      ' [' || coalesce(array_to_string(
        (select array_agg(distinct qt.tag order by qt.tag limit 3) from question_tags qt where qt.question_id = hp.id), ', '), '') || ']' as title_snippet,
    -- complicated predicate: is controversial if score ~ 0 but many answers and mixed votes
    case
      when hp.score between -2 and 2
           and hp.answercount >= 5
           and (select sum(case when v.votetypeid=2 then 1 when v.votetypeid=3 then -1 else 0 end) from votes v where v.postid = hp.id) between -5 and 5
      then true else false end as is_controversial,
    -- correlated subquery for top answerer in last 6 months (ties broken by reputation)
    (select u2.id from posts a
      join users u2 on u2.id = a.owneruserid
      where a.parentid = hp.id and a.creationdate >= now() - interval '6 months'
      group by u2.id
      order by count(*) desc, max(u2.reputation) desc
      limit 1) as recent_top_answerer,
    -- JSON-like aggregation using set operations
    (select json_agg(row_to_json(x)) from (
       select p2.id as answer_id, p2.owneruserid, p2.score, p2.creationdate
       from posts p2 where p2.parentid = hp.id
       order by p2.score desc nulls last limit 5
    ) x) as top_answers_sample
  from hot_posts hp
  left join users u on u.id = hp.owneruserid
  left join user_activity ua on ua.user_id = u.id
  left join lateral (
    select distinct unnest(string_to_array(substring(hp.tags from 2 for greatest(char_length(hp.tags)-2,0)), '><')) as tag
  ) t on true
  left join tag_stats ts on ts.tag = t.tag
  left join link_metrics lm on lm.question_id = hp.id
  left join badge_velocity bv on bv.userid = u.id
  where hp.rn <= 500
)
select
  bc.*,
  -- additional computed columns with null logic, set operators and windowed percentiles
  (case when bc.questions_total is null then 0 else bc.questions_total end) as questions_total_zeroed,
  percentile_disc(0.75) within group (order by coalesce(bc.hotness,0)) over () as global_hotness_p75,
  dense_rank() over (order by coalesce(bc.hotness,0) desc) as hot_rank_global
from benchmark_core bc
where (bc.hotness > (select coalesce(percentile_disc(0.9) within group (order by hotness) from hot_posts)) OR bc.velocity > 1.5)
  and (bc.is_controversial = true OR bc.questions_last_30d > 2 OR coalesce(bc.duplicates_in,0) > 0)
order by bc.hotness desc nulls last, bc.velocity desc
limit 200;