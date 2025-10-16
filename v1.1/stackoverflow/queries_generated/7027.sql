-- {"query": "7027.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2073} 
with
-- recent active questions enriched
RecentQ as (
  select p.id, p.title, p.creationdate, p.owneruserid, p.viewcount, p.score,
         coalesce(p.answercount,0) as answercount,
         coalesce(p.favoritecount,0) as favorites,
         substring(coalesce(p.tags,'') from 2 for char_length(coalesce(p.tags,''))-2) as raw_tags,
         -- split tags roughly by >< into an array-like text for pattern matching
         replace(replace(coalesce(p.tags,''),'><','|'),'<>','|') as tag_pipe
  from posts p
  where p.posttypeid = 1
    and p.creationdate >= now() - interval '365 days'
),
-- compute per-question aggregated stats: top answer, distinct commenters, recent edits
QStats as (
  select q.id,
         -- top scoring answer (score, age)
         (select a.id from posts a
           where a.parentid = q.id and a.posttypeid = 2
           order by a.score desc nulls last, a.creationdate asc nulls last
           limit 1) as top_answer_id,
         (select a.score from posts a
           where a.parentid = q.id and a.posttypeid = 2
           order by a.score desc nulls last, a.creationdate asc nulls last
           limit 1) as top_answer_score,
         (select count(*) from posts a where a.parentid = q.id and a.posttypeid = 2) as answers_total,
         (select count(distinct c.userid) from comments c where c.postid = q.id) as distinct_commenters,
         -- most recent non-system edit from PostHistory (exclude community bump type 50)
         (select ph.creationdate from posthistory ph
            where ph.postid = q.id and ph.posthistorytypeid not in (50)
            order by ph.creationdate desc
            limit 1) as last_history_date,
         -- earliest comment containing code-like ticks or stack-tag references
         (select min(c.creationdate) from comments c
            where c.postid = q.id and (c.text ~ E'`.+`' or c.text ilike '%stackoverflow.com%')) as first_meta_comment
  from RecentQ q
),
-- user aggregate: activity, badge influence, reputation trend
UserAgg as (
  select u.id, u.displayname,
         u.reputation,
         u.views,
         u.upvotes,
         u.downvotes,
         date_trunc('day', u.creationdate) as created_day,
         -- badges counts by class
         sum(case when b.class = 1 then 1 else 0 end) filter (where b.id is not null) as gold_badges,
         sum(case when b.class = 2 then 1 else 0 end) filter (where b.id is not null) as silver_badges,
         sum(case when b.class = 3 then 1 else 0 end) filter (where b.id is not null) as bronze_badges,
         -- last activity across posts/comments/votes
         greatest(
           coalesce((select max(p.lastactivitydate) from posts p where p.owneruserid = u.id), '1970-01-01'::timestamp),
           coalesce((select max(c.creationdate) from comments c where c.userid = u.id), '1970-01-01'::timestamp),
           coalesce((select max(v.creationdate) from votes v where v.userid = u.id), '1970-01-01'::timestamp)
         ) as last_active
  from users u
  left join badges b on b.userid = u.id
  group by u.id, u.displayname, u.reputation, u.views, u.upvotes, u.downvotes, u.creationdate
),
-- heavy windowed ranking of questions by multiple signals with NULL handling
RankedQ as (
  select r.*,
         qs.top_answer_id, qs.top_answer_score, qs.answers_total, qs.distinct_commenters,
         row_number() over (order by coalesce(r.score,0) desc, coalesce(r.viewcount,0) desc, coalesce(qs.answers_total,0) desc) as rank_by_popularity,
         rank() over (partition by coalesce(r.owneruserid,-1) order by coalesce(r.score,0) desc) as owner_local_rank,
         ntile(10) over (order by coalesce(r.score,0) desc) as score_decile
  from RecentQ r
  left join QStats qs on qs.id = r.id
),
-- find related questions via postlinks and tag similarity combined, include set operators
Related as (
  select distinct rl.postid as qid, rl.relatedpostid as related_id, lt.name as linktype
  from postlinks rl
  left join linktypes lt on lt.id = rl.linktypeid
  where rl.postid in (select id from RecentQ)
    and rl.relatedpostid is not null

  union

  select q.id as qid, t2.id as related_id, 'tag-similar' as linktype
  from posts q
  join posts t2 on t2.posttypeid = 1 and t2.id <> q.id
  where q.id in (select id from RecentQ)
    and ( -- tag intersection heuristic using LIKE on the pipe-converted tags
         replace(replace(coalesce(q.tags,''),'><','|'),'<>','|') like '%' || replace(replace(coalesce(t2.tags,''),'><','|'),'<>','|') || '%'
         or replace(replace(coalesce(t2.tags,''),'><','|'),'<>','|') like '%' || replace(replace(coalesce(q.tags,''),'><','|'),'<>','|') || '%'
    )
  limit 1000
),
-- compute combined score including recency decay, author reputation influence, badge multipliers, and engagement
FinalScore as (
  select rq.*,
         ua.displayname as owner_name,
         ua.reputation as owner_reputation,
         ua.gold_badges, ua.silver_badges, ua.bronze_badges,
         coalesce(rq.score,0) as raw_score,
         -- recency factor: newer -> higher, decays over year
         exp(-extract(epoch from (now() - rq.creationdate))/(60*60*24*90)) as recency_factor,
         -- engagement factor
         (1 + least(coalesce(rq.answers_total,0),10) * 0.15 + ln(1 + coalesce(rq.distinct_commenters,0)) * 0.25 + (case when rq.favorites > 0 then 0.2 else 0 end)) as engagement_factor,
         -- badge influence scaled
         (1 + coalesce(ua.gold_badges,0) * 0.05 + coalesce(ua.silver_badges,0) * 0.02 + coalesce(ua.bronze_badges,0) * 0.01) as badge_factor,
         -- final composite score (complex expression with NULL-safe arithmetic)
         ( (coalesce(rq.score,0) * 1.2 + ln(1+coalesce(rq.viewcount,0)) * 0.8 + coalesce(rq.favorites,0) * 2.5)
           * (1 + (coalesce(ua.reputation,0) / (1000 + coalesce(ua.reputation,0))) )
           * (coalesce(exp(-extract(epoch from (now() - rq.creationdate))/(60*60*24*180)), 0.1) + recency_factor) / 2
           * engagement_factor * badge_factor
         ) as composite_score
  from RankedQ rq
  left join UserAgg ua on ua.id = rq.owneruserid
),
-- pick top related per question using correlated subquery with NULL logic
TopRelated as (
  select f.*,
         (select r.related_id from Related r where r.qid = f.id
            order by case when r.linktype = 'Duplicate' then 0 else 1 end, r.linktype, r.related_id
            limit 1) as best_related_id,
         (select r.linktype from Related r where r.qid = f.id
            order by case when r.linktype = 'Duplicate' then 0 else 1 end, r.linktype, r.related_id
            limit 1) as best_related_type
  from FinalScore f
)
select
  tr.id,
  left(coalesce(tr.title,''),160) as short_title,
  tr.creationdate,
  tr.owneruserid,
  tr.owner_name,
  tr.owner_reputation,
  tr.answers_total,
  tr.top_answer_id,
  tr.top_answer_score,
  tr.distinct_commenters,
  tr.favorites,
  tr.viewcount,
  tr.raw_score,
  round(tr.composite_score::numeric,4) as composite_score,
  tr.rank_by_popularity,
  tr.score_decile,
  tr.last_history_date,
  tr.first_meta_comment,
  tr.best_related_id,
  tr.best_related_type,
  -- string expression combining tags and title for full-text-ish fingerprint
  substring(regexp_replace(coalesce(tr.tag_pipe,''),'[^\w\|]',' ','g') from 1 for 200) || ' :: ' || left(coalesce(tr.title,''),80) as fingerprint,
  -- detect presence of nullable fields and classify
  case when tr.owneruserid is null then 'orphan' when tr.owner_reputation < 50 then 'lowrep' else 'established' end as owner_classification
from TopRelated tr
where tr.composite_score is not null
order by tr.composite_score desc, tr.rank_by_popularity asc
limit 250;