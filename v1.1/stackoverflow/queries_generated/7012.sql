-- {"query": "7012.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2247} 
with
-- recent active questions with tag arrays and heuristic quality score
recent_q as (
  select
    p.id,
    p.title,
    p.creationdate,
    p.score,
    p.viewcount,
    p.answercount,
    p.owneruserid,
    p.tags,
    -- split tags '<tag1><tag2>' -> array of tag names (Postgres style)
    case when p.tags is null then array[]::text[] else string_to_array(substring(p.tags,2,length(p.tags)-2), '><') end as tag_array,
    -- heuristic: score weighted by recency and answers, with null-safe math
    (coalesce(p.score,0) * 1.0) 
      + (coalesce(p.answercount,0) * 2.5)
      + greatest(0, 100 - extract(epoch from (now() - p.creationdate))/3600)::int * 0.01 as quality_score
  from posts p
  where p.posttypeid = 1
    and p.creationdate >= (now() - interval '180 days')
),
-- top answerers (by answers in last year) with window functions
answers_last_year as (
  select a.id, a.parentid as questionid, a.owneruserid, a.creationdate, a.score,
         row_number() over (partition by a.owneruserid order by sum(a.score) over (partition by a.owneruserid) desc, count(*) over (partition by a.owneruserid) desc) as rn_per_user
  from posts a
  where a.posttypeid = 2
    and a.creationdate >= (now() - interval '365 days')
),
user_answer_stats as (
  select
    u.id as userid,
    u.displayname,
    count(al.id) filter (where al.creationdate >= now() - interval '365 days') as answers_365,
    coalesce(sum(al.score),0) as total_answer_score_365,
    coalesce(avg(al.score),0) as avg_answer_score,
    max(al.creationdate) as last_answer_date
  from users u
  left join posts al on al.owneruserid = u.id and al.posttypeid = 2 and al.creationdate >= now() - interval '365 days'
  group by u.id, u.displayname
  having count(al.id) > 0
),
-- compute per-question aggregate signals: comments, edits, close events, linked posts, favorites (votes)
question_signals as (
  select
    q.id as questionid,
    coalesce(q.commentcount,0) as comment_count_meta,
    coalesce(q.favoritecount,0) as favorite_count,
    coalesce(sum(case when ph.posthistorytypeid in (10,11,12,13,14,15,19,20) then 1 else 0 end),0) as moderation_events,
    coalesce(sum(case when pl.linktypeid = 3 then 1 else 0 end),0) as duplicate_links_incoming,
    coalesce(sum(case when pl.linktypeid = 1 then 1 else 0 end),0) as outbound_links_count,
    coalesce(sum(v.vote_type_id = 5)::int,0) as favorites_via_votes -- for systems where favorite stored as votetype 5
  from posts q
  left join posthistory ph on ph.postid = q.id
  left join postlinks pl on pl.postid = q.id
  left join votes v on v.postid = q.id
  where q.posttypeid = 1
  group by q.id, q.commentcount, q.favoritecount
),
-- per-tag popularity and danger (questions closed ratio) using tag explosion
tag_expanded as (
  select
    rq.id as questionid,
    t.tagname
  from recent_q rq
  cross join lateral unnest(rq.tag_array) t(tagname)
),
tag_aggregates as (
  select
    te.tagname,
    count(distinct te.questionid) as recent_questions,
    sum(case when q.closeddate is not null then 1 else 0 end) as closed_count,
    coalesce(sum(q.viewcount),0) as views_sum,
    coalesce(avg(q.score),0) as avg_score
  from tag_expanded te
  join posts q on q.id = te.questionid
  group by te.tagname
),
-- compute user reputation movement and badge density
user_reputation_badges as (
  select
    u.id,
    u.displayname,
    u.reputation,
    (select count(*) from badges b where b.userid = u.id and b.date >= now() - interval '365 days') as badges_last_year,
    (select count(*) filter (where b.class = 1) from badges b where b.userid = u.id) as gold_badges,
    (select count(*) filter (where b.class = 2) from badges b where b.userid = u.id) as silver_badges,
    (select count(*) filter (where b.class = 3) from badges b where b.userid = u.id) as bronze_badges
  from users u
  where u.reputation is not null
),
-- pick candidate questions joined with their accepted answers and owner info
candidate_q as (
  select
    rq.*,
    qs.comment_count_meta,
    qs.favorite_count,
    qs.duplicate_links_incoming,
    qs.outbound_links_count,
    ua.displayname as asker_name,
    ua.reputation as asker_rep,
    aa.id as accepted_answer_id,
    aa.owneruserid as accepted_answer_owner,
    aa.score as accepted_answer_score,
    aa.creationdate as accepted_answer_date
  from recent_q rq
  left join question_signals qs on qs.questionid = rq.id
  left join posts aa on aa.id = rq.acceptedanswerid
  left join users ua on ua.id = rq.owneruserid
),
-- enrich with correlated subqueries: top comment author on the question, number of distinct editors
question_enriched as (
  select
    cq.*,
    -- top commenter by comment score then recent
    (select c.userid from comments c where c.postid = cq.id group by c.userid order by count(*) desc, max(c.creationdate) desc limit 1) as top_commenter_id,
    (select u.displayname from users u where u.id = (select c.userid from comments c where c.postid = cq.id group by c.userid order by count(*) desc, max(c.creationdate) desc limit 1)) as top_commenter_name,
    (select count(distinct ph.userid) from posthistory ph where ph.postid = cq.id and ph.userid is not null) as distinct_editors,
    (select bool_or(ph.posthistorytypeid = 10) from posthistory ph where ph.postid = cq.id) as ever_closed_flag
  from candidate_q cq
),
-- final selection with window analytics, string manipulation, and set operators
final_ranked as (
  select
    qe.id,
    qe.title,
    left(coalesce(qe.title, ''), 180) || case when length(coalesce(qe.title,'')) > 180 then '...' else '' end as short_title,
    qe.creationdate,
    qe.quality_score,
    qe.score,
    qe.viewcount,
    qe.answercount,
    qe.comment_count_meta,
    qe.favorite_count,
    qe.duplicate_links_incoming,
    qe.outbound_links_count,
    qe.asker_name,
    qe.asker_rep,
    qe.accepted_answer_id,
    qe.accepted_answer_owner,
    qe.accepted_answer_score,
    qe.top_commenter_id,
    qe.top_commenter_name,
    qe.distinct_editors,
    qe.ever_closed_flag,
    -- tag list as comma separated string, normalized: lowercase and trimmed
    (select string_agg(lower(t.tagname), ',') from unnest(qe.tag_array) t(tagname)) as tags_compressed,
    -- popularity rank among recent questions by quality_score and viewcount
    rank() over (order by qe.quality_score desc, qe.viewcount desc) as pop_rank,
    dense_rank() over (partition by qe.asker_rep/NULLIF(NULLIF(qe.asker_rep,0),0) order by qe.quality_score desc) as rep_partition_rank,
    -- compute a risky_score: closed_flag, duplicates, low answers, low score
    (case when qe.ever_closed_flag then 50 else 0 end)
      + (coalesce(qe.duplicate_links_incoming,0) * 5)
      + greatest(0, 5 - coalesce(qe.answercount,0)) * 3
      + (case when coalesce(qe.score,0) < 0 then abs(qe.score) * 2 else 0 end) as risky_score
  from question_enriched qe
)
select
  f.*,
  ta.tagname,
  tg.recent_questions,
  tg.closed_count,
  tg.views_sum,
  tg.avg_score,
  uas.displayname as top_answerer_name,
  uas.answers_365,
  uas.total_answer_score_365,
  urb.reputation,
  urb.badges_last_year,
  urb.gold_badges,
  urb.silver_badges,
  urb.bronze_badges
from final_ranked f
-- join to tag aggregates: explode tags_compressed and join to tag_aggregates
left join lateral (
  select unnest(string_to_array(coalesce(f.tags_compressed,''), ',')) as tagname
) ta on true
left join tag_aggregates tg on tg.tagname = ta.tagname
-- join to a top answerer for the question (highest scoring answer within 90 days)
left join lateral (
  select a.owneruserid, u.displayname, count(*) over () as cnt
  from posts a
  join users u on u.id = a.owneruserid
  where a.parentid = f.id
    and a.posttypeid = 2
    and a.creationdate >= now() - interval '90 days'
  order by a.score desc nulls last, a.creationdate asc
  limit 1
) uas on true
left join user_reputation_badges urb on urb.id = coalesce(f.accepted_answer_owner, uas.owneruserid, f.top_commenter_id)
where
  -- filter for interesting candidates: high quality or risky or popular
  (f.quality_score >= 5 or f.risky_score >= 8 or f.viewcount >= 1000)
  and (f.tags_compressed is not null and f.tags_compressed != '')
order by f.pop_rank, f.risky_score desc, tg.recent_questions desc
limit 200;