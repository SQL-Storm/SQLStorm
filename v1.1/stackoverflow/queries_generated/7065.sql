-- {"query": "7065.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2209} 
with
-- recent active questions with tag extraction and normalized tag rows
QuestionBase as (
  select
    p.id,
    p.title,
    p.body,
    p.owneruserid,
    p.creationdate,
    p.score,
    p.viewcount,
    coalesce(p.answercount,0) as answercount,
    p.acceptedanswerid,
    nullif(p.tags,'') as raw_tags,
    -- explode pseudo-array: tags stored like '<tag1><tag2>'
    regexp_split_to_table(substring(p.tags from 2 for greatest(char_length(p.tags)-2,0)), '><') as tag
  from posts p
  where p.posttypeid = 1
    and p.creationdate >= now() - interval '2 years'
    and p.viewcount is not null
),
-- per-question aggregates: top answers, comment stats, vote distributions
AnswerAgg as (
  select
    q.id as question_id,
    count(a.id) filter (where a.posttypeid = 2) as answers_total,
    max(a.score) filter (where a.posttypeid = 2) as best_answer_score,
    -- correlated subquery style: distance in days between question and accepted answer creation
    case when q.acceptedanswerid is not null then
      (select extract(epoch from (a2.creationdate - q.creationdate))/86400
       from posts a2 where a2.id = q.acceptedanswerid)
    else null end as days_to_accepted,
    -- average comment length across question+answers
    (select avg(char_length(c.text)) from comments c where c.postid in (
       select id from posts p2 where (p2.id = q.id or p2.parentid = q.id)
    )) as avg_comment_len,
    -- votes distribution on answers (set operators via filtered aggregates)
    sum(case when v.votetypeid = 2 then 1 else 0 end) as answer_upvotes,
    sum(case when v.votetypeid = 3 then 1 else 0 end) as answer_downvotes
  from QuestionBase q
  left join posts a on a.parentid = q.id and a.posttypeid = 2
  left join votes v on v.postid = a.id
  group by q.id, q.acceptedanswerid, q.creationdate
),
-- user-level rolling metrics and badge influence using window functions
UserMetrics as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    u.creationdate as user_created,
    count(distinct p.id) filter (where p.posttypeid = 1 and p.creationdate >= u.creationdate) over (partition by u.id) as questions_posted,
    count(distinct b.id) filter (where b.class = 1) over (partition by u.id) as gold_badges,
    count(distinct b.id) filter (where b.class = 2) over (partition by u.id) as silver_badges,
    count(distinct b.id) filter (where b.class = 3) over (partition by u.id) as bronze_badges,
    -- recency-weighted reputation proxy: reputation divided by account age in years
    u.reputation / nullif(greatest(extract(epoch from (now() - u.creationdate))/31557600, 0.0001),0.0001) as rep_per_year,
    -- last access gap
    extract(epoch from (now() - u.lastaccessdate))/86400 as days_since_last_access
  from users u
  left join posts p on p.owneruserid = u.id
  left join badges b on b.userid = u.id
  group by u.id, u.displayname, u.reputation, u.creationdate, u.lastaccessdate
),
-- tag popularity and co-occurrence: compute tag-level stats and top co-tags
TagStats as (
  select
    t.tag,
    count(*) as questions_with_tag,
    avg(q.viewcount) as avg_views,
    percentile_cont(0.5) within group (order by q.score) as median_score,
    -- string expressions: synthetic normalized tag key
    lower(regexp_replace(t.tag, '[^a-z0-9]+','_', 'g')) as tag_key
  from QuestionBase t
  join posts q on q.id = t.id
  group by t.tag
),
TagCooccurrence as (
  select
    t1.tag as tag,
    t2.tag as co_tag,
    count(*) as co_count,
    round(100.0 * count(*) / nullif((select count(*) from posts p where p.id in (select id from QuestionBase where tag = t1.tag)),0),2) as percent_of_tag
  from QuestionBase t1
  join QuestionBase t2 on t1.id = t2.id and t1.tag <> t2.tag
  group by t1.tag, t2.tag
),
-- identify posts that were migrated/closed/edited heavily via PostHistory complex predicates
PostHistorySignals as (
  select
    ph.postid,
    sum(case when ph.posthistorytypeid in (10,11,12,13,35,36) then 1 else 0 end) as closure_or_migrate_events,
    sum(case when ph.posthistorytypeid in (5,8,24) then 1 else 0 end) as body_edit_events,
    max(ph.creationdate) as last_history_date,
    bool_or(ph.comment ilike '%duplicate%') as hinted_duplicate
  from posthistory ph
  where ph.creationdate >= now() - interval '3 years'
  group by ph.postid
),
-- assemble heavy-weight candidate set with complex predicates & calculations
Candidates as (
  select
    q.*,
    ta.questions_with_tag,
    ta.avg_views,
    ta.tag_key,
    aa.answers_total,
    aa.best_answer_score,
    aa.days_to_accepted,
    aa.avg_comment_len,
    phs.closure_or_migrate_events,
    phs.body_edit_events,
    phs.hinted_duplicate,
    um.user_id,
    um.displayname as author_name,
    um.reputation as author_rep,
    um.gold_badges,
    um.rep_per_year,
    -- calculated score combining many signals, uses null logic and type casting
    (
      coalesce(q.score,0) * 1.5
      + coalesce(aa.best_answer_score,0) * 2.2
      + coalesce(ta.avg_views,0) / nullif(GREATEST(q.viewcount,1),1) * 10
      - coalesce(phs.closure_or_migrate_events,0) * 5
      + log(1 + coalesce(um.rep_per_year,0)) * 3
      + case when aa.days_to_accepted is null then -2 else greatest(0, 5 - aa.days_to_accepted) end
      + case when ta.questions_with_tag > 1000 then 2 else 0 end
    )::numeric(12,4) as composite_score
  from QuestionBase q
  left join TagStats ta on ta.tag = q.tag
  left join AnswerAgg aa on aa.question_id = q.id
  left join PostHistorySignals phs on phs.postid = q.id
  left join Users u on u.id = q.owneruserid
  left join UserMetrics um on um.user_id = u.id
  where q.tag is not null
),
-- rank candidates per tag using window functions and tie-breaking by recency & author reputation
Ranked as (
  select
    c.*,
    row_number() over (
      partition by c.tag_key
      order by c.composite_score desc,
               c.answercount desc,
               c.viewcount desc,
               c.creationdate desc,
               c.author_rep desc nulls last
    ) as rn,
    dense_rank() over (
      partition by c.tag_key
      order by c.composite_score desc
    ) as dr
  from Candidates c
),
-- select top N per tag plus a global heavy-tail sample via set operators
TopPerTag as (
  select * from Ranked where rn <= 5
),
GlobalHeavyTail as (
  select *
  from Ranked
  where composite_score >= (
    select percentile_disc(0.95) within group (order by composite_score) from Ranked
  )
)
-- final output unions and complex ordering, including correlated subquery to fetch a sample comment
select
  t.id as question_id,
  t.title,
  left(regexp_replace(coalesce(t.body,'')::text, '<[^>]*>',' ','g'),500) as body_snippet,
  t.tag,
  t.tag_key,
  t.questions_with_tag,
  t.avg_views,
  t.answers_total,
  t.best_answer_score,
  t.days_to_accepted,
  t.avg_comment_len,
  t.closure_or_migrate_events,
  t.body_edit_events,
  t.hinted_duplicate,
  t.author_name,
  t.author_rep,
  t.gold_badges,
  t.composite_score,
  t.rn,
  t.dr,
  -- correlated scalar subquery: a representative comment with null handling and length truncation
  (select left(text,200) from comments c where c.postid = t.id order by c.score desc nulls last, c.creationdate asc limit 1) as top_comment_snippet,
  -- compute an entropy-like tag diversity metric using co-occurrence counts
  (select round(sum(-p*ln(p))::numeric,6) from (
     select co_count::numeric / nullif((select sum(co_count) from tagcooccurrence tc2 where tc2.tag = t.tag),0) as p
     from tagcooccurrence tc where tc.tag = t.tag
  ) sub(p)) as tag_diversity_entropy
from (
  select * from TopPerTag
  union
  select * from GlobalHeavyTail
) t
-- complex predicates for final filtering: prefer recent, active, non-community, and avoid deleted users
where (t.creationdate >= now() - interval '18 months' or t.composite_score >= 100)
  and (t.owneruserid is not null and t.owneruserid > 0)
  and (t.hinted_duplicate = false or t.closure_or_migrate_events = 0)
order by t.tag_key asc, t.composite_score desc, t.creationdate desc
limit 100;