-- {"query": "959.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2766} 
with recent_users as (
  select u.id as user_id,
         u.displayname,
         u.reputation,
         u.creationdate,
         u.location,
         date_trunc('month', u.creationdate) as signup_month,
         coalesce(nullif(trim(split_part(coalesce(u.websiteurl,''),'//',2)),''), 'none') as website_domain
  from users u
  where u.creationdate >= now() - interval '5 years'
),
q as (
  select p.id as post_id,
         p.owneruserid as user_id,
         p.creationdate,
         p.score,
         p.viewcount,
         p.answercount,
         p.commentcount,
         p.favoritecount,
         p.tags,
         p.title
  from posts p
  where p.posttypeid = 1
),
a as (
  select p.id as post_id,
         p.parentid as question_id,
         p.owneruserid as user_id,
         p.creationdate,
         p.score
  from posts p
  where p.posttypeid = 2
),
votes_cte as (
  select v.postid,
         sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
         sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
         sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites,
         sum(case when v.votetypeid = 8 then coalesce(v.bountyamount,0) else 0 end) as bounty_started,
         sum(case when v.votetypeid = 9 then coalesce(v.bountyamount,0) else 0 end) as bounty_awarded,
         count(*) as total_votes,
         min(v.creationdate) as first_vote_at,
         max(v.creationdate) as last_vote_at
  from votes v
  group by v.postid
),
comments_agg as (
  select c.postid,
         count(*) as comments_count,
         sum(case when c.score > 0 then 1 else 0 end) as pos_comments,
         sum(case when c.score < 0 then 1 else 0 end) as neg_comments,
         max(c.score) as max_comment_score,
         string_agg(left(c.text, 80), ' | ' order by c.score desc, c.creationdate) as sample_comments
  from comments c
  group by c.postid
),
tag_expanded as (
  select q.post_id,
         unnest(string_to_array(substring(q.tags, 2, greatest(length(q.tags)-2,0)), '><')) as tag
  from q
  where q.tags is not null
),
top_tag_users as (
  select u.id as user_id,
         t.tag,
         count(*) as posts_with_tag,
         rank() over (partition by t.tag order by count(*) desc, u.id) as rnk_by_tag
  from tag_expanded t
  join posts p on p.id = t.post_id
  join users u on u.id = p.owneruserid
  group by u.id, t.tag
),
postlinks_agg as (
  select pl.postid,
         sum(case when pl.linktypeid = 1 then 1 else 0 end) as linked_count,
         sum(case when pl.linktypeid = 3 then 1 else 0 end) as duplicate_count,
         max(case when pl.linktypeid = 3 then pl.relatedpostid end) as example_duplicate_of
  from postlinks pl
  group by pl.postid
),
edits as (
  select ph.postid,
         count(*) filter (where ph.posthistorytypeid in (4,5,6,7,8,9,24)) as edit_events,
         min(ph.creationdate) filter (where ph.posthistorytypeid in (4,5,6,24)) as first_edit_at,
         max(ph.creationdate) filter (where ph.posthistorytypeid in (4,5,6,24)) as last_edit_at,
         count(*) filter (where ph.posthistorytypeid = 10) as close_events,
         max((ph.comment ~ '^[0-9]+$')::int * ph.comment::int) filter (where ph.posthistorytypeid = 10) as last_close_reason_code
  from posthistory ph
  group by ph.postid
),
answers_agg as (
  select a.question_id,
         count(*) as answer_count,
         avg(a.score) as avg_answer_score,
         max(a.score) as max_answer_score,
         min(a.creationdate) as first_answer_at,
         max(a.creationdate) as last_answer_at
  from a
  group by a.question_id
),
badges_agg as (
  select b.userid,
         count(*) as total_badges,
         sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
         sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
         sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
         max(b.date) as last_badge_at
  from badges b
  group by b.userid
),
user_activity as (
  select u.id as user_id,
         count(*) filter (where p.posttypeid = 1) as questions_posted,
         count(*) filter (where p.posttypeid = 2) as answers_posted,
         coalesce(sum(p.score) filter (where p.posttypeid in (1,2)),0) as total_post_score,
         max(p.lastactivitydate) as last_activity,
         count(distinct date_trunc('day', p.creationdate)) as active_days
  from users u
  left join posts p on p.owneruserid = u.id
  group by u.id
),
question_metrics as (
  select q.post_id,
         q.user_id,
         q.creationdate as question_created_at,
         q.score as question_score,
         coalesce(q.viewcount,0) as views,
         coalesce(v.upvotes,0) as upvotes,
         coalesce(v.downvotes,0) as downvotes,
         coalesce(v.favorites,0) as favorites,
         coalesce(c.comments_count,0) as comments_count,
         coalesce(c.pos_comments,0) as pos_comments,
         coalesce(c.neg_comments,0) as neg_comments,
         coalesce(pa.linked_count,0) as linked_count,
         coalesce(pa.duplicate_count,0) as duplicate_count,
         coalesce(pa.example_duplicate_of,0) as example_duplicate_of,
         coalesce(e.edit_events,0) as edit_events,
         e.first_edit_at,
         e.last_edit_at,
         coalesce(e.close_events,0) as close_events,
         e.last_close_reason_code,
         coalesce(ans.answer_count,0) as answers,
         ans.avg_answer_score,
         ans.max_answer_score,
         ans.first_answer_at,
         ans.last_answer_at,
         case when q.answercount is null then coalesce(ans.answer_count,0) else q.answercount end as answercount_reported,
         length(coalesce(q.title,'')) as title_len,
         cardinality(string_to_array(coalesce(substring(q.tags, 2, greatest(length(q.tags)-2,0)) ,''), '><')) as tag_count
  from q
  left join votes_cte v on v.postid = q.post_id
  left join comments_agg c on c.postid = q.post_id
  left join postlinks_agg pa on pa.postid = q.post_id
  left join edits e on e.postid = q.post_id
  left join answers_agg ans on ans.question_id = q.post_id
),
ranked_questions as (
  select qm.*,
         row_number() over (partition by qm.user_id order by qm.views desc, qm.question_score desc, qm.post_id) as rn_views,
         row_number() over (partition by qm.user_id order by coalesce(qm.upvotes - qm.downvotes,0) desc, qm.post_id) as rn_netvotes,
         ntile(10) over (order by coalesce(qm.views,0) desc) as views_decile,
         rank() over (order by (coalesce(qm.upvotes,0) - coalesce(qm.downvotes,0)) desc nulls last) as sitewide_vote_rank
  from question_metrics qm
),
power_users as (
  select ru.user_id,
         ru.displayname,
         ru.reputation,
         ru.signup_month,
         coalesce(b.total_badges,0) as total_badges,
         coalesce(b.gold_badges,0) as gold_badges,
         coalesce(b.silver_badges,0) as silver_badges,
         coalesce(b.bronze_badges,0) as bronze_badges,
         ua.questions_posted,
         ua.answers_posted,
         ua.total_post_score,
         ua.last_activity,
         ua.active_days,
         ru.website_domain
  from recent_users ru
  left join badges_agg b on b.userid = ru.user_id
  left join user_activity ua on ua.user_id = ru.user_id
  where coalesce(ua.questions_posted,0) + coalesce(ua.answers_posted,0) > 0
),
picked_question as (
  select rq.*
  from ranked_questions rq
  where rq.rn_views <= 3
     or rq.rn_netvotes = 1
),
eligible as (
  select pq.post_id,
         pq.user_id,
         pq.views_decile,
         pq.sitewide_vote_rank,
         pq.tag_count,
         pq.edit_events,
         pq.close_events,
         pq.answers,
         pq.answercount_reported,
         pq.last_answer_at,
         pq.duplicate_count,
         pq.upvotes,
         pq.downvotes,
         pq.favorites,
         pq.comments_count,
         pq.title_len
  from picked_question pq
  where (pq.views_decile <= 3 and pq.answers >= 1)
     or (pq.duplicate_count = 0 and pq.tag_count between 2 and 5)
)
select
  pu.user_id,
  pu.displayname,
  pu.reputation,
  pu.signup_month,
  pu.total_badges,
  pu.gold_badges,
  pu.silver_badges,
  pu.bronze_badges,
  pu.questions_posted,
  pu.answers_posted,
  pu.total_post_score,
  pu.last_activity,
  pu.active_days,
  pu.website_domain,
  e.post_id,
  coalesce(pt.name, 'Unknown') as post_type_name,
  rq.question_score,
  rq.views,
  e.views_decile,
  e.sitewide_vote_rank,
  e.tag_count,
  e.edit_events,
  e.close_events,
  e.answers,
  e.answercount_reported,
  coalesce(date_part('epoch', e.last_answer_at - rq.question_created_at)/3600.0, null) as hours_to_last_answer,
  e.duplicate_count,
  coalesce(e.upvotes,0) - coalesce(e.downvotes,0) as net_votes,
  e.favorites,
  e.comments_count,
  e.title_len,
  case
    when e.close_events > 0 then 'closed'
    when e.duplicate_count > 0 then 'duplicate'
    when e.answers = 0 and coalesce(e.upvotes,0) + coalesce(e.downvotes,0) = 0 then 'unanswered-unvoted'
    else 'active'
  end as question_state,
  case when tt.rnk_by_tag = 1 then tt.tag else null end as top_tag_by_user,
  coalesce(ca.sample_comments, '') as comment_samples,
  pl.example_duplicate_of,
  left(coalesce(q.title,''), 140) as title_sample
from eligible e
join ranked_questions rq on rq.post_id = e.post_id
left join q on q.post_id = e.post_id
left join posts p on p.id = e.post_id
left join posttypes pt on pt.id = p.posttypeid
left join power_users pu on pu.user_id = rq.user_id
left join comments_agg ca on ca.postid = e.post_id
left join postlinks_agg pl on pl.postid = e.post_id
left join lateral (
  select ttu.tag, ttu.rnk_by_tag
  from top_tag_users ttu
  where ttu.user_id = rq.user_id
  order by ttu.rnk_by_tag
  limit 1
) tt on true
where pu.user_id is not null
and (
  pu.reputation >= 1000
  or (pu.gold_badges + pu.silver_badges) >= 5
  or (pu.questions_posted + pu.answers_posted) >= 50
)
and (
  e.net_votes is distinct from null
  or e.favorites > 0
  or e.comments_count > 0
)
order by pu.reputation desc, e.views_decile, e.post_id
limit 500;