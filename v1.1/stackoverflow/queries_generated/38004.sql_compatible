with recent_users as (
  select u.id as user_id, u.displayname, u.reputation, u.creationdate
  from users u
  where u.creationdate >= (select max(creationdate) - interval '365 days' from users)
),
top_tags as (
  select t.tagname, t.count, t.id
  from tags t
  where t.count > (select percentile_disc(0.95) within group (order by count) from tags)
),
question_tags as (
  select p.id as question_id,
         unnest(string_to_array(substring(p.tags, 2, length(p.tags)-2), '><')) as tag
  from posts p
  where p.posttypeid = 1
),
hot_questions as (
  select qt.tag, p.id as question_id, p.score, p.viewcount, p.owneruserid, p.creationdate
  from question_tags qt
  join posts p on p.id = qt.question_id
  where p.score >= (select percentile_disc(0.90) within group (order by score) from posts where posttypeid = 1 and score is not null)
    and p.viewcount >= (select percentile_disc(0.90) within group (order by viewcount) from posts where posttypeid = 1 and viewcount is not null)
),
accepted_answers as (
  select q.id as question_id, q.acceptedanswerid as answer_id
  from posts q
  where q.posttypeid = 1 and q.acceptedanswerid is not null
),
answer_metrics as (
  select a.parentid as question_id,
         count(*) as answers_total,
         sum(case when a.score > 0 then 1 else 0 end) as answers_positive,
         max(a.score) as max_answer_score,
         avg(a.score) as avg_answer_score
  from posts a
  where a.posttypeid = 2
  group by a.parentid
),
comment_activity as (
  select c.postid as post_id,
         count(*) as comments_total,
         sum(case when c.score > 0 then 1 else 0 end) as comments_positive
  from comments c
  group by c.postid
),
favorite_votes as (
  select v.postid as post_id, count(*) as favorites
  from votes v
  where v.votetypeid = 5
  group by v.postid
),
dup_links as (
  select pl.postid as question_id, count(*) as duplicate_links
  from postlinks pl
  where pl.linktypeid = 3
  group by pl.postid
),
edit_bursts as (
  select ph.postid as post_id,
         count(*) filter (where ph.posthistorytypeid in (4,5,6,7,8,9,24)) as edit_events,
         min(ph.creationdate) as first_edit,
         max(ph.creationdate) as last_edit
  from posthistory ph
  group by ph.postid
),
user_quality as (
  select u.id as user_id,
         u.reputation,
         coalesce(sum(case when v.votetypeid = 2 then 1 when v.votetypeid = 3 then -1 else 0 end),0) as net_votes_cast,
         coalesce(sum(case when b.class = 1 then 5 when b.class = 2 then 3 when b.class = 3 then 1 else 0 end),0) as badge_score
  from users u
  left join votes v on v.userid = u.id
  left join badges b on b.userid = u.id
  group by u.id, u.reputation
),
tag_engagement as (
  select qt.tag,
         count(distinct p.id) as questions_count,
         sum(coalesce(am.answers_total,0)) as total_answers,
         sum(coalesce(ca.comments_total,0)) as total_comments,
         sum(coalesce(fv.favorites,0)) as total_favorites,
         avg(p.score) as avg_q_score,
         avg(p.viewcount) as avg_q_views
  from question_tags qt
  join posts p on p.id = qt.question_id
  left join answer_metrics am on am.question_id = p.id
  left join comment_activity ca on ca.post_id = p.id
  left join favorite_votes fv on fv.post_id = p.id
  group by qt.tag
),
tag_bench_base as (
  select ht.tag,
         ht.question_id,
         ht.score,
         ht.viewcount,
         ht.owneruserid,
         am.answers_total,
         am.answers_positive,
         am.max_answer_score,
         am.avg_answer_score,
         coalesce(ca.comments_total,0) as comments_total,
         coalesce(ca.comments_positive,0) as comments_positive,
         coalesce(fv.favorites,0) as favorites,
         coalesce(dl.duplicate_links,0) as duplicate_links,
         coalesce(eb.edit_events,0) as edit_events
  from hot_questions ht
  left join answer_metrics am on am.question_id = ht.question_id
  left join comment_activity ca on ca.post_id = ht.question_id
  left join favorite_votes fv on fv.post_id = ht.question_id
  left join dup_links dl on dl.question_id = ht.question_id
  left join edit_bursts eb on eb.post_id = ht.question_id
),
owner_enriched as (
  select tb.*, rq.displayname, uq.reputation as owner_reputation, uq.badge_score, uq.net_votes_cast
  from tag_bench_base tb
  left join recent_users rq on rq.user_id = tb.owneruserid
  left join user_quality uq on uq.user_id = tb.owneruserid
),
agg_by_tag as (
  select
    oe.tag,
    count(*) as hot_q,
    avg(oe.score) as avg_q_score,
    avg(oe.viewcount) as avg_q_views,
    percentile_disc(0.5) within group (order by oe.viewcount) as p50_views,
    percentile_disc(0.9) within group (order by oe.viewcount) as p90_views,
    sum(coalesce(oe.answers_total,0)) as sum_answers,
    avg(CASE WHEN coalesce(oe.answers_total,0) = 0 THEN NULL ELSE coalesce(oe.answers_positive,0) * 1.0 / coalesce(oe.answers_total,0) END) as avg_answer_pos_ratio,
    avg(oe.max_answer_score) as avg_max_answer_score,
    avg(oe.avg_answer_score) as avg_ans_score,
    sum(oe.comments_total) as sum_comments,
    sum(oe.favorites) as sum_favorites,
    sum(oe.duplicate_links) as sum_dups,
    avg(oe.edit_events) as avg_edits,
    avg(coalesce(oe.owner_reputation,0)) as avg_owner_rep,
    avg(coalesce(oe.badge_score,0)) as avg_owner_badges,
    avg(coalesce(oe.net_votes_cast,0)) as avg_owner_net_votes
  from owner_enriched oe
  group by oe.tag
),
ranked_tags as (
  select
    abt.tag,
    abt.hot_q,
    abt.avg_q_score,
    abt.avg_q_views,
    abt.p50_views,
    abt.p90_views,
    abt.sum_answers,
    abt.avg_answer_pos_ratio,
    abt.avg_max_answer_score,
    abt.avg_ans_score,
    abt.sum_comments,
    abt.sum_favorites,
    abt.sum_dups,
    abt.avg_edits,
    abt.avg_owner_rep,
    abt.avg_owner_badges,
    abt.avg_owner_net_votes,
    te.questions_count,
    te.total_answers,
    te.total_comments,
    te.total_favorites,
    te.avg_q_score as tag_pool_avg_q_score,
    te.avg_q_views as tag_pool_avg_q_views,
    row_number() over (order by abt.avg_q_views desc, abt.sum_answers desc) as rank_by_views_answers,
    dense_rank() over (order by abt.avg_q_score desc) as rank_by_score,
    dense_rank() over (order by abt.sum_favorites desc) as rank_by_favorites
  from agg_by_tag abt
  join tag_engagement te on te.tag = abt.tag
  where abt.hot_q >= 5
)
select
  rt.tag,
  rt.hot_q,
  rt.avg_q_score,
  rt.avg_q_views,
  rt.p50_views,
  rt.p90_views,
  rt.sum_answers,
  round(rt.avg_answer_pos_ratio, 3) as avg_answer_pos_ratio,
  rt.avg_max_answer_score,
  round(rt.avg_ans_score, 3) as avg_ans_score,
  rt.sum_comments,
  rt.sum_favorites,
  rt.sum_dups,
  round(rt.avg_edits, 2) as avg_edits,
  round(rt.avg_owner_rep, 0) as avg_owner_rep,
  round(rt.avg_owner_badges, 2) as avg_owner_badges,
  round(rt.avg_owner_net_votes, 2) as avg_owner_net_votes,
  rt.questions_count as tag_pool_questions,
  rt.total_answers as tag_pool_answers,
  rt.total_comments as tag_pool_comments,
  rt.total_favorites as tag_pool_favorites,
  round(rt.tag_pool_avg_q_score, 2) as tag_pool_avg_q_score,
  round(rt.tag_pool_avg_q_views, 2) as tag_pool_avg_q_views,
  rt.rank_by_views_answers,
  rt.rank_by_score,
  rt.rank_by_favorites
from ranked_tags rt
where rt.tag in (select tagname from top_tags)
order by rt.rank_by_views_answers, rt.rank_by_score, rt.rank_by_favorites
limit 50;