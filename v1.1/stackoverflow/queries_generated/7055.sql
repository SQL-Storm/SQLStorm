-- {"query": "7055.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1879} 
with
-- recent active posts with tag normalization
QuestionBase as (
  select p.id,
         p.title,
         p.owneruserid,
         p.creationdate,
         p.score,
         p.viewcount,
         coalesce(p.answercount,0) as answercount,
         coalesce(p.favoritecount,0) as favoritecount,
         p.tags,
         -- normalized tag list as one tag per row via regexp (works in Postgres); fallback to whole tags string if null
         regexp_split_to_table(
           coalesce(substring(p.tags from 2 for char_length(coalesce(p.tags,'')) - 2), ''),
           '><'
         ) as tag
  from posts p
  where p.posttypeid = 1
    and p.creationdate >= now() - interval '3 years'
),
-- heavy hitters per question: aggregated vote and comment stats
QuestionMetrics as (
  select q.id,
         count(distinct v.id) filter (where v.votetypeid in (2,3)) as votes_cnt,
         sum(case when v.votetypeid = 2 then 1 when v.votetypeid = 3 then -1 else 0 end) as votes_balance,
         count(distinct c.id) as comments_cnt,
         max(coalesce(u.reputation,0)) as asker_reputation,
         -- ratio expressions including null-safe math
         case when count(distinct v.id) = 0 then null else round(1.0 * sum(case when v.votetypeid = 2 then 1 when v.votetypeid = 3 then -1 else 0 end) / nullif(count(distinct v.id),0)::numeric,4) end as avg_vote_ratio
  from QuestionBase q
  left join votes v on v.postid = q.id
  left join comments c on c.postid = q.id
  left join users u on u.id = q.owneruserid
  group by q.id
),
-- correlated subquery: best answer summary per question
BestAnswer as (
  select a.postid,
         a.ans_id,
         a.ans_score,
         a.ans_age_days,
         a.ans_ownerid,
         a.ans_owner_rep
  from (
    select an.parentid as postid,
           an.id as ans_id,
           an.score as ans_score,
           extract(epoch from (an.creationdate - q.creationdate))/86400.0 as ans_age_days,
           an.owneruserid as ans_ownerid,
           coalesce(u.reputation,0) as ans_owner_rep,
           row_number() over (partition by an.parentid
                              order by an.score desc nulls last, an.creationdate asc) rn
    from posts an
    join posts q on q.id = an.parentid and q.posttypeid = 1
    left join users u on u.id = an.owneruserid
    where an.posttypeid = 2
      and an.creationdate >= now() - interval '5 years'
  ) a
  where a.rn = 1
),
-- tag popularity rollup with window functions and tie-breaking
TagPopularity as (
  select tag,
         count(distinct q.id) as questions_with_tag,
         sum(q.score) as total_score,
         avg(q.answercount) as avg_answers,
         rank() over (order by count(distinct q.id) desc, sum(q.score) desc) as popularity_rank
  from QuestionBase q
  group by tag
),
-- recent edits and close events using PostHistory with complicated JSON/text logic
PostEvents as (
  select ph.postid,
         max(case when ph.posthistorytypeid in (5,2) then ph.creationdate end) as last_body_edit,
         bool_or(ph.posthistorytypeid = 10) as has_close_event,
         string_agg(distinct ph.comment, ' || ' order by ph.creationdate desc) filter (where ph.comment is not null) as concat_comments,
         -- try to extract duplicate targets from JSON-ish Text field when PostHistoryTypeId = 10 or 35 (some DB dumps)
         array_remove(array_agg(distinct regexp_replace(ph.text, '[^0-9,]', '', 'g') ) , NULL) as possible_json_numbers
  from posthistory ph
  where ph.creationdate >= now() - interval '5 years'
  group by ph.postid
),
-- user badge velocity: correlated counts and windows per user filtered by recent timeframe
UserBadgeVelocity as (
  select b.userid,
         count(*) filter (where b.date >= now() - interval '1 year') as badges_last_year,
         count(*) filter (where b.date >= now() - interval '30 days') as badges_last_30d,
         dense_rank() over (order by count(*) filter (where b.date >= now() - interval '1 year') desc) as badge_velocity_rank
  from badges b
  group by b.userid
),
-- cross-join seeds to produce deterministic permutation for benchmarking CPU
PermutationSeed as (
  select generate_series(1,500) as s
),
-- final selection: interesting mix of CTEs, outer joins, correlated subqueries, set ops, windowing, string ops, null logic
Final as (
  select qb.id as question_id,
         qb.title,
         qb.tag,
         tm.votes_cnt,
         tm.votes_balance,
         tm.comments_cnt,
         ba.ans_id as top_answer_id,
         ba.ans_score,
         round(ba.ans_age_days::numeric,2) as top_answer_age_days,
         ba.ans_ownerid,
         ba.ans_owner_rep,
         tp.questions_with_tag,
         tp.total_score,
         pe.has_close_event,
         pe.concat_comments,
         ubv.badges_last_year,
         ubv.badges_last_30d,
         -- synthetic complexity: compute a weighted hotness score with null-safe arithmetic, string weighting, and coalesce
         (
           coalesce(tm.votes_balance,0) * 1.5
           + coalesce(qb.viewcount,0)::numeric / nullif(coalesce(tp.questions_with_tag,1),1)
           + coalesce(ubv.badges_last_year,0) * 2
           - coalesce(pe.has_close_event::int,0) * 20
           + coalesce(ba.ans_score,0) * 3
         ) / nullif(1 + coalesce(tp.popularity_rank,100),0) as hotness_score,
         -- string expression and null handling for title fingerprint and tag-joined
         left(md5(coalesce(qb.title,'')) || '_' || replace(coalesce(qb.tag,''),' ','_'), 48) as title_fingerprint,
         tp.popularity_rank
  from QuestionBase qb
  left join QuestionMetrics tm on tm.id = qb.id
  left join BestAnswer ba on ba.postid = qb.id
  left join TagPopularity tp on tp.tag = qb.tag
  left join PostEvents pe on pe.postid = qb.id
  left join UserBadgeVelocity ubv on ubv.userid = qb.owneruserid
)
select f.*,
       -- window: rank within the same tag by hotness descending
       rank() over (partition by f.tag order by f.hotness_score desc nulls last) as tag_hot_rank,
       -- correlate: count other recent questions by same owner using lateral
       coalesce(other_q.cnt_by_owner,0) as owner_recent_questions,
       -- include a deterministic but heavy join via permutation seed to stress planner
       p.s as permutation_index,
       -- compute a complex predicate combining many booleans
       ( (f.votes_cnt > 10 and f.comments_cnt > 5) or (f.badges_last_30d > 0 and f.ans_score > 0) or (f.popularity_rank <= 50) ) as complex_selector
from Final f
left join lateral (
  select count(*) as cnt_by_owner
  from posts p
  where p.owneruserid = f.ans_ownerid
    and p.creationdate >= now() - interval '2 years'
) other_q on true
join PermutationSeed p on (p.s % nullif((coalesce(f.question_id,1)),1) = (coalesce(f.question_id,1) % 500))
where
  -- apply a complicated filter with null logic, regex, and set operators
  (f.hotness_score is not null and f.hotness_score > 5)
  and (f.tag not in ('deprecated','status-completed') or f.tag is null)
  and (f.title not ~* '^(test|dummy|tmp)' or f.title is null)
  and exists (
    select 1 from tags t where t.tagname = f.tag and t.count > 10
  )
order by f.hotness_score desc nulls last, f.questions_with_tag desc, f.question_id
limit 250;