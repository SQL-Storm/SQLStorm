with recent_users as (
  select u.id as user_id, u.displayname, u.reputation, u.creationdate
  from users u
  where u.creationdate >= (select max(creationdate) - interval '365 days' from users)
),
active_questions as (
  select p.id as question_id,
         p.owneruserid as asker_id,
         p.creationdate,
         p.score,
         p.viewcount,
         p.tags,
         coalesce(p.answercount, 0) as answercount
  from posts p
  where p.posttypeid = 1
    and p.creationdate >= (select max(creationdate) - interval '365 days' from posts where posttypeid = 1)
),
answers as (
  select a.id as answer_id,
         a.parentid as question_id,
         a.owneruserid as answerer_id,
         a.creationdate as answer_created,
         a.score as answer_score
  from posts a
  where a.posttypeid = 2
),
comments_by_post as (
  select c.postid,
         count(*) as comment_cnt,
         sum(c.score) as comment_score_sum,
         sum(case when c.score > 0 then 1 else 0 end) as positive_comments
  from comments c
  group by c.postid
),
votes_agg as (
  select v.postid,
         sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
         sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
         sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites,
         sum(case when v.votetypeid in (8,9) then coalesce(v.bountyamount,0) else 0 end) as bounty_total,
         sum(case when v.votetypeid in (8,9) then 1 else 0 end) as bounty_events
  from votes v
  group by v.postid
),
badge_tiers as (
  select b.userid,
         sum(case when b.class = 1 then 1 else 0 end) as gold_cnt,
         sum(case when b.class = 2 then 1 else 0 end) as silver_cnt,
         sum(case when b.class = 3 then 1 else 0 end) as bronze_cnt,
         count(*) as total_badges,
         max(b.date) as last_badge_date
  from badges b
  group by b.userid
),
tag_expand as (
  select q.question_id,
         -- Replace PostgreSQL string_to_array/unnest pattern with standard SQL: split tags by '><' after trimming leading '<' and trailing '>'
         -- Using regexp_substr + hierarchical generation is dialect-specific; keep PostgreSQL approach but avoid casts
         unnest(string_to_array(substring(q.tags, 2, length(q.tags)-2), '><')) as tagname
  from active_questions q
  where q.tags is not null and q.tags like '<%>'
),
top_tags as (
  select t.tagname,
         count(*) as tag_q_count
  from tag_expand t
  group by t.tagname
  having count(*) >= 50
),
question_quality as (
  select q.question_id,
         q.asker_id,
         q.creationdate,
         q.score,
         q.viewcount,
         q.answercount,
         va.upvotes,
         va.downvotes,
         va.favorites,
         va.bounty_total,
         va.bounty_events,
         coalesce(cp.comment_cnt,0) as comment_cnt,
         coalesce(cp.comment_score_sum,0) as comment_score_sum,
         coalesce(cp.positive_comments,0) as positive_comments,
         coalesce(va.upvotes,0) - coalesce(va.downvotes,0) as net_votes,
         case when q.viewcount > 0 then (coalesce(va.upvotes,0) * 1.0 / q.viewcount) else 0 end as upvote_view_ratio
  from active_questions q
  left join votes_agg va on va.postid = q.question_id
  left join comments_by_post cp on cp.postid = q.question_id
),
first_answer as (
  select a.question_id,
         min(a.answer_created) as first_answer_time
  from answers a
  group by a.question_id
),
answerers as (
  select a.question_id,
         count(distinct a.answerer_id) as distinct_answerers,
         avg(a.answer_score) as avg_answer_score,
         max(a.answer_score) as max_answer_score
  from answers a
  group by a.question_id
),
post_links_agg as (
  select pl.relatedpostid as question_id,
         sum(case when pl.linktypeid = 1 then 1 else 0 end) as inbound_links,
         sum(case when pl.linktypeid = 3 then 1 else 0 end) as inbound_duplicates
  from postlinks pl
  group by pl.relatedpostid
),
close_events as (
  select ph.postid as question_id,
         min(case when ph.posthistorytypeid = 10 then ph.creationdate end) as first_close_time,
         sum(case when ph.posthistorytypeid = 10 then 1 else 0 end) as close_votes,
         sum(case when ph.posthistorytypeid = 11 then 1 else 0 end) as reopen_votes
  from posthistory ph
  where ph.posthistorytypeid in (10,11)
  group by ph.postid
),
question_tags as (
  select q.question_id,
         array_agg(t.tagname order by t.tagname) filter (where tt.tagname is not null) as common_tags
  from tag_expand t
  left join top_tags tt on tt.tagname = t.tagname
  right join active_questions q on q.question_id = t.question_id
  group by q.question_id
),
asker_profile as (
  select u.id as user_id,
         u.displayname,
         u.reputation,
         u.creationdate as user_creation,
         u.views,
         u.upvotes,
         u.downvotes,
         bt.gold_cnt,
         bt.silver_cnt,
         bt.bronze_cnt,
         bt.total_badges
  from users u
  left join badge_tiers bt on bt.userid = u.id
),
scored_questions as (
  select qq.question_id,
         qq.asker_id,
         qq.creationdate,
         qq.score,
         qq.viewcount,
         qq.answercount,
         qq.upvotes,
         qq.downvotes,
         qq.favorites,
         qq.bounty_total,
         qq.bounty_events,
         qq.comment_cnt,
         qq.comment_score_sum,
         qq.positive_comments,
         qq.net_votes,
         qq.upvote_view_ratio,
         fa.first_answer_time,
         extract(epoch from (fa.first_answer_time - qq.creationdate))/3600.0 as hours_to_first_answer,
         an.distinct_answerers,
         an.avg_answer_score,
         an.max_answer_score,
         pla.inbound_links,
         pla.inbound_duplicates,
         ce.first_close_time,
         ce.close_votes,
         ce.reopen_votes
  from question_quality qq
  left join first_answer fa on fa.question_id = qq.question_id
  left join answerers an on an.question_id = qq.question_id
  left join post_links_agg pla on pla.question_id = qq.question_id
  left join close_events ce on ce.question_id = qq.question_id
),
asker_enriched as (
  select sq.*,
         ap.displayname as asker_name,
         ap.reputation as asker_reputation,
         ap.user_creation as asker_joined,
         ap.views as asker_profile_views,
         ap.upvotes as asker_upvotes_given,
         ap.downvotes as asker_downvotes_given,
         ap.gold_cnt as asker_gold,
         ap.silver_cnt as asker_silver,
         ap.bronze_cnt as asker_bronze,
         ap.total_badges as asker_badges
  from scored_questions sq
  left join asker_profile ap on ap.user_id = sq.asker_id
),
final_agg as (
  select
    aq.question_id,
    aq.creationdate as question_created,
    aq.score as question_score,
    aq.viewcount,
    aq.answercount,
    aq.upvotes,
    aq.downvotes,
    aq.net_votes,
    aq.upvote_view_ratio,
    aq.favorites,
    aq.bounty_total,
    aq.bounty_events,
    aq.comment_cnt,
    aq.comment_score_sum,
    aq.positive_comments,
    aq.first_answer_time,
    aq.hours_to_first_answer,
    aq.distinct_answerers,
    aq.avg_answer_score,
    aq.max_answer_score,
    aq.inbound_links,
    aq.inbound_duplicates,
    aq.first_close_time,
    aq.close_votes,
    aq.reopen_votes,
    at.common_tags,
    aq.asker_id,
    aq.asker_name,
    aq.asker_reputation,
    aq.asker_joined,
    aq.asker_profile_views,
    aq.asker_upvotes_given,
    aq.asker_downvotes_given,
    aq.asker_gold,
    aq.asker_silver,
    aq.asker_bronze,
    aq.asker_badges
  from asker_enriched aq
  left join question_tags at on at.question_id = aq.question_id
)
select
  f.question_id,
  f.asker_id,
  f.asker_name,
  f.asker_reputation,
  f.asker_badges,
  f.common_tags,
  f.viewcount,
  f.question_score,
  f.net_votes,
  f.favorites,
  f.bounty_total,
  f.comment_cnt,
  f.distinct_answerers,
  f.avg_answer_score,
  f.hours_to_first_answer,
  f.inbound_links,
  f.inbound_duplicates,
  f.close_votes,
  f.reopen_votes,
  rank() over (order by
    coalesce(f.net_votes,0) * 2
    + coalesce(f.favorites,0) * 1.5
    + coalesce(f.viewcount,0) * 0.002
    + coalesce(f.bounty_total,0) * 0.05
    + coalesce(f.distinct_answerers,0) * 1.2
    + coalesce(10.0 / nullif(f.hours_to_first_answer,0), 0)
    + coalesce(f.inbound_links,0) * 0.75
    - coalesce(f.inbound_duplicates,0) * 1.5
    - coalesce(f.downvotes,0) * 0.5
  desc) as perf_rank
from final_agg f
where f.viewcount >= 100
  and coalesce(f.distinct_answerers,0) >= 1
order by perf_rank
limit 200;