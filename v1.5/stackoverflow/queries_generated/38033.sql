-- {"query": "38033.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 2222} 
with recent_users as (
  select u.id as user_id, u.displayname, u.reputation, u.creationdate
  from users u
  where u.creationdate >= (select max(creationdate) - interval '365 days' from users)
),
question_posts as (
  select p.id as post_id, p.owneruserid as user_id, p.creationdate, p.score, p.viewcount, p.tags, p.title
  from posts p
  where p.posttypeid = 1
),
answer_posts as (
  select p.id as post_id, p.parentid as question_id, p.owneruserid as user_id, p.creationdate, p.score
  from posts p
  where p.posttypeid = 2
),
tag_exploded as (
  select qp.post_id, lower(trim(t.tag)) as tag
  from question_posts qp
  cross join lateral unnest(string_to_array(substring(qp.tags, 2, length(qp.tags)-2), '><')) as t(tag)
),
top_tags as (
  select tag, count(*) as q_count
  from tag_exploded
  group by tag
  having count(*) > 100
),
q_activity as (
  select
    qp.post_id,
    qp.user_id,
    qp.creationdate,
    qp.score as q_score,
    qp.viewcount,
    count(a.post_id) as answer_count,
    coalesce(sum(case when v.votetypeid = 2 then 1 when v.votetypeid = 3 then -1 else 0 end), 0) as net_votes,
    max(coalesce(a.score, 0)) as max_answer_score
  from question_posts qp
  left join answer_posts a on a.question_id = qp.post_id
  left join votes v on v.postid = qp.post_id and v.votetypeid in (2,3)
  group by qp.post_id, qp.user_id, qp.creationdate, qp.score, qp.viewcount
),
comment_stats as (
  select c.postid as post_id,
         count(*) as comment_count,
         sum(case when c.score >= 5 then 1 else 0 end) as hot_comment_count,
         max(c.creationdate) as last_comment_date
  from comments c
  group by c.postid
),
badge_agg as (
  select b.userid as user_id,
         sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
         sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
         sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
         sum(case when b.tagbased = 1 then 1 else 0 end) as tag_badges
  from badges b
  group by b.userid
),
dup_links as (
  select pl.postid as post_id, count(*) as duplicate_links
  from postlinks pl
  where pl.linktypeid = 3
  group by pl.postid
),
closure_events as (
  select ph.postid as post_id,
         min(case when ph.posthistorytypeid = 10 then ph.creationdate end) as first_closed_at,
         min(case when ph.posthistorytypeid = 11 then ph.creationdate end) as first_reopened_at,
         count(*) filter (where ph.posthistorytypeid = 10) as close_count,
         count(*) filter (where ph.posthistorytypeid = 11) as reopen_count
  from posthistory ph
  where ph.posthistorytypeid in (10,11)
  group by ph.postid
),
hotness as (
  select
    qa.post_id,
    -- a synthetic "hotness" score mixing votes, answers, views, recency, and comments
    (qa.net_votes * 4
     + qa.answer_count * 3
     + least(qa.viewcount, 10000) / 200
     + qa.q_score * 2
     + coalesce(cs.comment_count, 0)
    )::numeric
    / greatest(extract(epoch from (now() - qa.creationdate)) / 86400.0 + 2.0, 2.0) as hot_score
  from q_activity qa
  left join comment_stats cs on cs.post_id = qa.post_id
),
answer_latency as (
  select
    a.question_id as post_id,
    min(a.creationdate) as first_answer_at,
    avg(extract(epoch from (a.creationdate - q.creationdate)) / 60.0) as avg_minutes_to_answer
  from answer_posts a
  join posts q on q.id = a.question_id
  group by a.question_id, q.creationdate
),
user_engagement as (
  select
    qa.user_id,
    count(*) as questions_count,
    avg(qa.net_votes) as avg_q_net_votes,
    avg(qa.answer_count) as avg_answers_per_q,
    percentile_cont(0.9) within group (order by qa.viewcount) as p90_q_views,
    sum(case when h.hot_score > 5 then 1 else 0 end) as hot_q_count
  from q_activity qa
  join hotness h on h.post_id = qa.post_id
  group by qa.user_id
),
tag_quality as (
  select
    te.tag,
    count(*) as q_cnt,
    avg(qa.net_votes) as avg_net_votes,
    avg(qa.answer_count) as avg_answers,
    avg(h.hot_score) as avg_hot,
    sum(case when cl.close_count > 0 then 1 else 0 end)::float / count(*) as close_rate
  from tag_exploded te
  join q_activity qa on qa.post_id = te.post_id
  join hotness h on h.post_id = te.post_id
  left join closure_events cl on cl.post_id = te.post_id
  group by te.tag
  having count(*) >= 50
),
qualified_questions as (
  select
    qa.post_id,
    qa.user_id,
    qa.creationdate,
    qa.q_score,
    qa.viewcount,
    qa.answer_count,
    qa.net_votes,
    qa.max_answer_score,
    coalesce(cs.comment_count, 0) as comment_count,
    coalesce(cs.hot_comment_count, 0) as hot_comment_count,
    coalesce(dl.duplicate_links, 0) as duplicate_links,
    h.hot_score,
    al.first_answer_at,
    al.avg_minutes_to_answer,
    cl.first_closed_at,
    cl.first_reopened_at,
    cl.close_count,
    cl.reopen_count
  from q_activity qa
  left join comment_stats cs on cs.post_id = qa.post_id
  left join dup_links dl on dl.post_id = qa.post_id
  left join hotness h on h.post_id = qa.post_id
  left join answer_latency al on al.post_id = qa.post_id
  left join closure_events cl on cl.post_id = qa.post_id
)
select
  qq.post_id,
  u.displayname as owner_displayname,
  u.reputation,
  coalesce(ba.gold_badges,0) as gold_badges,
  coalesce(ba.silver_badges,0) as silver_badges,
  coalesce(ba.bronze_badges,0) as bronze_badges,
  ue.questions_count,
  round(ue.avg_q_net_votes::numeric, 2) as avg_q_net_votes,
  round(ue.p90_q_views::numeric, 0) as p90_q_views,
  qq.creationdate as question_created,
  qq.q_score,
  qq.viewcount,
  qq.answer_count,
  qq.net_votes,
  qq.max_answer_score,
  qq.comment_count,
  qq.hot_comment_count,
  qq.duplicate_links,
  round(coalesce(qq.hot_score, 0)::numeric, 3) as hot_score,
  round(coalesce(qq.avg_minutes_to_answer, 0)::numeric, 1) as avg_minutes_to_answer,
  qq.first_answer_at,
  qq.first_closed_at,
  qq.first_reopened_at,
  qq.close_count,
  qq.reopen_count,
  array(
    select t.tag
    from tag_exploded t
    where t.post_id = qq.post_id
    order by t.tag
    limit 5
  ) as sample_tags,
  array(
    select tq.tag
    from tag_exploded t2
    join top_tags tq on tq.tag = t2.tag
    where t2.post_id = qq.post_id
    order by tq.q_count desc, tq.tag
    limit 3
  ) as top_tags_on_q,
  (
    select jsonb_agg(jsonb_build_object(
      'commentId', c.id,
      'score', c.score,
      'created', c.creationdate,
      'text', left(c.text, 140)
    ) order by c.score desc nulls last, c.creationdate asc)
    from comments c
    where c.postid = qq.post_id
    fetch first 5 rows only
  ) as top_comments,
  (
    select count(*)
    from votes v
    where v.postid = qq.post_id and v.votetypeid = 5
  ) as favorites_count_estimate,
  (
    select jsonb_build_object(
      'tag', tq.tag,
      'qCnt', tq.q_cnt,
      'avgNet', round(tq.avg_net_votes::numeric,2),
      'avgAns', round(tq.avg_answers::numeric,2),
      'avgHot', round(tq.avg_hot::numeric,2),
      'closeRate', round((tq.close_rate*100)::numeric,2)
    )
    from tag_quality tq
    where tq.tag in (
      select t.tag
      from tag_exploded t
      where t.post_id = qq.post_id
      order by t.tag
      limit 1
    )
  ) as primary_tag_quality
from qualified_questions qq
join users u on u.id = qq.user_id
left join badge_agg ba on ba.user_id = u.id
left join user_engagement ue on ue.user_id = u.id
where qq.creationdate >= now() - interval '1095 days'
  and qq.viewcount >= 50
  and qq.answer_count >= 1
  and coalesce(qq.hot_score, 0) > 1
order by qq.hot_score desc, qq.viewcount desc
limit 200;