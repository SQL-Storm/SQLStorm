-- {"query": "154.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 2862} 
with
-- explode tags into one row per tag per question
question_tags as (
  select p.id as question_id,
         lower(trim(both ' ' from t)) as tag
  from posts p
  cross join lateral (
    select unnest(string_to_array(substring(coalesce(p.tags, ''), 2, greatest(length(coalesce(p.tags, ''))-2,0)), '><')) as t
  ) s
  where p.posttypeid = 1 and coalesce(p.tags,'') <> ''
),

-- basic aggregated stats per question (answers, views, score) and derived fields
question_stats as (
  select q.id,
         q.title,
         q.creationdate,
         q.viewcount,
         q.score,
         q.answercount,
         q.acceptedanswerid,
         q.owneruserid,
         q.tags,
         coalesce(q.answercount,0) filter (where q.posttypeid=1) as answers_reported,
         -- time to accept in hours (null if no accepted answer)
         case when q.acceptedanswerid is not null then
           extract(epoch from (select p2.creationdate from posts p2 where p2.id = q.acceptedanswerid) - q.creationdate)/3600.0
         end as hours_to_accept,
         -- boolean flags
         case when q.closeddate is not null then 1 else 0 end as is_closed,
         case when q.communityowneddate is not null then 1 else 0 end as community_owned
  from posts q
  where q.posttypeid = 1
),

-- per-question answer-level aggregates (median-ish answer score, top answer score, avg)
answer_agg as (
  select a.parentid as question_id,
         count(*) as answers_total,
         max(a.score) as top_answer_score,
         avg(a.score) as avg_answer_score,
         -- approximate median via percentile_disc
         percentile_disc(0.5) within group (order by a.score) as median_answer_score,
         sum(case when a.id = (select p.acceptedanswerid from posts p where p.id = a.parentid) then 1 else 0 end) as accepted_marker_count
  from posts a
  where a.posttypeid = 2
  group by a.parentid
),

-- badge counts and latest badge time for askers
asker_badges as (
  select u.id as user_id,
         count(b.id) as total_badges,
         sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
         sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
         sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
         max(b.date) as last_badge_date
  from users u
  left join badges b on b.userid = u.id
  group by u.id
),

-- recent activity: last edit or last history entry per question
recent_activity as (
  select ph.postid,
         max(coalesce(ph.creationdate, post.lasteditdate, post.lastactivitydate)) as last_hist_date,
         -- collect last meaningful PostHistory types in a JSON-ish string (concat)
         string_agg(distinct coalesce(pht.name, ph.comment, ph.text::text), ' | ' order by ph.creationdate desc) as recent_history_summary
  from posthistory ph
  left join posthistorytypes pht on pht.id = ph.posthistorytypeid
  left join posts post on post.id = ph.postid
  group by ph.postid
),

-- top commenter per question (correlated subquery using comments)
top_commenter as (
  select c.postid as question_id,
         (select c2.userid
          from comments c2
          where c2.postid = c.postid
            and c2.userid is not null
          group by c2.userid
          order by count(*) desc, max(c2.creationdate) desc
          limit 1) as top_commenter_userid,
         (select count(*) from comments c3 where c3.postid = c.postid) as total_comments
  from comments c
  where exists(select 1 from posts p where p.id = c.postid and p.posttypeid = 1)
  group by c.postid
),

-- linked questions: how many duplicates/links each question has and most-linked related post id
link_agg as (
  select l.postid as question_id,
         count(*) as links_out,
         sum(case when l.linktypeid = 3 then 1 else 0 end) as duplicates_out,
         max(l.relatedpostid) filter (where l.linktypeid = 3) as some_duplicate_relatedid
  from postlinks l
  group by l.postid
),

-- for benchmarking: compute a composite "interest_score" using many pieces and NULL-safe math
interest_base as (
  select qs.*,
         coalesce(aa.answers_total,0) as answers_total,
         coalesce(aa.top_answer_score,0) as top_answer_score,
         coalesce(aa.avg_answer_score,0)::numeric as avg_answer_score,
         coalesce(aa.median_answer_score,0)::numeric as median_answer_score,
         coalesce(ab.total_badges,0) as asker_badges,
         coalesce(la.links_out,0) as links_out,
         coalesce(la.duplicates_out,0) as dup_count,
         coalesce(ra.total_comments,0) as total_comments,
         coalesce(ract.last_hist_date, qs.lastactivitydate, qs.creationdate) as last_activity,
         -- tag heuristics: length, number of tags
         (case when qs.tags is null or qs.tags = '' then 0
               else array_length(string_to_array(substring(qs.tags,2,length(qs.tags)-2),'><'),1) end) as tag_count,
         length(coalesce(qs.title,'')) as title_len,
         -- string expressions and NULL logic in computed popularity
         (coalesce(qs.viewcount,0) * 0.3
          + coalesce(qs.score,0) * 4
          + coalesce(aa.top_answer_score,0) * 2
          + coalesce(aa.answers_total,0) * 5
          + sqrt(greatest(coalesce(ab.total_badges,0),1)) * 3
          - coalesce(qs.is_closed,0) * 50
          + ln(1 + coalesce(qs.viewcount,0)) * 2
          )::numeric as raw_popularity_metric
  from question_stats qs
  left join answer_agg aa on aa.question_id = qs.id
  left join asker_badges ab on ab.user_id = qs.owneruserid
  left join top_commenter ra on ra.question_id = qs.id
  left join link_agg la on la.question_id = qs.id
  left join recent_activity ract on ract.postid = qs.id
),

-- normalize and compute final score with window functions and ranking
ranked_questions as (
  select ib.*,
         -- time-decay factor: more recent activity -> boost
         greatest(0.1, exp(-extract(epoch from (now() - last_activity))/86400.0/30.0)) as recency_decay,
         -- tag diversity factor (penalize very few tags, cap)
         least(3.0, 1.0 + tag_count::numeric/2.0) as tag_diversity,
         -- final composite score using non-linear transforms, safe null handling
         (raw_popularity_metric * greatest(0.1, ln(2 + coalesce(tag_count,0))) * tag_diversity * greatest(0.05, coalesce(hours_to_accept,1)/24.0) * recency_decay) as composite_score,
         row_number() over (order by
           (raw_popularity_metric * greatest(0.1, ln(2 + coalesce(tag_count,0))) * recency_decay) desc,
           answers_total desc,
           viewcount desc
         ) as global_rank,
         dense_rank() over (partition by coalesce(owneruserid,-1) order by raw_popularity_metric desc) as owner_local_rank
  from interest_base ib
),

-- create a small UNION ALL set to include some synthetic "bucket" rows (for benchmarking set operators)
synthetic_buckets as (
  select -1 as id, 'SYNTHETIC: HOT'::varchar as title, now() as creationdate, 0::int as viewcount, 0::int as score, 0::int as answercount, null::int as acceptedanswerid, null::int as owneruserid, ''::varchar as tags,
         0::int as answers_total, 0::int as top_answer_score, 0.0::numeric as avg_answer_score, 0.0::numeric as median_answer_score,
         0::int as asker_badges, 0::int as links_out, 0::int as dup_count, 0::int as total_comments, now() as last_activity,
         0::int as tag_count, 0::int as title_len, 0.0::numeric as raw_popularity_metric, 1.0::numeric as recency_decay, 1.0::numeric as tag_diversity, 0.0::numeric as composite_score, 999999 as global_rank, 1 as owner_local_rank
  union all
  select -2, 'SYNTHETIC: COLD', now()-interval '365 days', 0, -10, 0, null, null, '', 0,0,0.0,0.0,0,0,0,0, now()-interval '365 days', 0,0,0.0,0.01,1.0,0.0, 999998, 1
)

-- final selection combining real ranked questions and synthetic buckets, with multiple joins and correlated subqueries for extra data
select rq.id,
       rq.title,
       rq.creationdate,
       rq.viewcount,
       rq.score,
       rq.answers_total,
       rq.avg_answer_score,
       rq.median_answer_score,
       rq.hours_to_accept,
       rq.tag_count,
       rq.title_len,
       rq.raw_popularity_metric,
       rq.composite_score,
       rq.global_rank,
       rq.owner_local_rank,
       coalesce(u.displayname, 'unknown') as asker_displayname,
       coalesce(u.reputation,0) as asker_reputation,
       coalesce(ab.gold_badges,0) as asker_gold,
       coalesce(ab.silver_badges,0) as asker_silver,
       coalesce(ab.bronze_badges,0) as asker_bronze,
       coalesce(tc.top_commenter_userid, null) as top_commenter_userid,
       coalesce(tc.total_comments,0) as total_comments,
       -- correlated subquery to fetch the most recent comment text for the question (NULL-safe, trimmed)
       (select substring(max(c.text) from 1 for 200)
        from comments c
        where c.postid = rq.id
          and c.text is not null) as latest_comment_snippet,
       -- left join one representative tag (first in alphabetical order) using tag expansion
       (select qt.tag from question_tags qt where qt.question_id = rq.id order by qt.tag limit 1) as representative_tag,
       -- existence checks for interesting conditions
       case when rq.dup_count > 0 then true else false end as has_duplicates,
       case when rq.is_closed = 1 then true else false end as is_closed,
       -- string expression to produce a short summary
       (coalesce(left(replace(replace(rq.title, E'\n',' '), E'\t',' '), 120), '') ||
        ' [' || coalesce((select qt.tag from question_tags qt where qt.question_id = rq.id order by qt.tag limit 1),'no-tag') || ']') as short_summary
from (
  select * from ranked_questions
  union all
  select * from synthetic_buckets
) rq
left join users u on u.id = rq.owneruserid
left join asker_badges ab on ab.user_id = u.id
left join top_commenter tc on tc.question_id = rq.id
-- filter and order for benchmarking: include top 200 by composite_score then add some negative and synthetic entries
where rq.composite_score is not null
order by rq.composite_score desc nulls last, rq.global_rank asc
limit 200;