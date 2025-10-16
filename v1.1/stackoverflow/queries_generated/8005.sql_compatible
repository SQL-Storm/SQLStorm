with recent_users as (
  select u.id as user_id,
         u.displayname,
         u.reputation,
         u.creationdate,
         u.location,
         coalesce(nullif(trim(split_part(coalesce(u.websiteurl, ''), '/', 3)), ''), 'none') as website_host,
         date_trunc('month', u.creationdate) as signup_month
  from users u
  where u.creationdate >= (select date_trunc('month', max(creationdate)) - interval '12 months' from users)
),
q_and_a as (
  select p.id,
         p.posttypeid,
         p.owneruserid,
         p.creationdate,
         p.score,
         p.viewcount,
         p.title,
         p.tags,
         p.acceptedanswerid,
         p.parentid
  from posts p
  where p.posttypeid in (1,2)
),
user_posts as (
  select ru.user_id,
         count(*) filter (where qa.posttypeid = 1) as q_count,
         count(*) filter (where qa.posttypeid = 2) as a_count,
         sum(qa.score) as total_score,
         avg(qa.score) as avg_score,
         max(qa.score) as max_score,
         min(qa.score) as min_score,
         count(distinct date_trunc('day', qa.creationdate)) as active_days
  from recent_users ru
  left join q_and_a qa
    on qa.owneruserid = ru.user_id
  group by ru.user_id
),
vote_agg as (
  select v.postid,
         count(*) filter (where v.votetypeid = 2) as upvotes,
         count(*) filter (where v.votetypeid = 3) as downvotes,
         count(*) filter (where v.votetypeid = 5) as favorites
  from votes v
  where v.creationdate >= (select coalesce(min(creationdate), timestamp '2024-10-01 12:34:56') - interval '5 years' from posts)
  group by v.postid
),
post_activity as (
  select qa.id as post_id,
         qa.owneruserid as user_id,
         qa.posttypeid,
         qa.creationdate,
         qa.score,
         qa.viewcount,
         va.upvotes,
         va.downvotes,
         va.favorites,
         coalesce(va.upvotes,0) - coalesce(va.downvotes,0) as net_votes,
         case when qa.posttypeid = 1 and qa.acceptedanswerid is not null then 1 else 0 end as has_accepted,
         array_length(string_to_array(coalesce(nullif(substring(qa.tags, 2, greatest(length(qa.tags)-2,0)), ''), ''), '><'), 1) as tag_count
  from q_and_a qa
  left join vote_agg va on va.postid = qa.id
),
dup_clusters as (
  select pl.relatedpostid as canonical_id,
         count(*) as dup_count,
         min(pl.creationdate) as first_dup,
         max(pl.creationdate) as last_dup
  from postlinks pl
  where pl.linktypeid = 3
  group by pl.relatedpostid
),
commenters as (
  select c.userid as commenter_id,
         c.postid,
         count(*) as comment_count,
         max(c.creationdate) as last_comment_date
  from comments c
  where c.userid is not null
  group by c.userid, c.postid
),
user_badges as (
  select b.userid,
         count(*) as badges_total,
         count(*) filter (where b.class = 1) as gold,
         count(*) filter (where b.class = 2) as silver,
         count(*) filter (where b.class = 3) as bronze,
         count(*) filter (where b.tagbased = true) as tag_badges
  from badges b
  group by b.userid
),
closed_reasons as (
  select ph.postid,
         max(case when ph.posthistorytypeid = 10 then ph.creationdate end) as closed_at,
         max(case when ph.posthistorytypeid = 10 and ph.comment ~ '^[0-9]+$' and cast(ph.comment as integer) = crt.id then crt.name end) as close_reason
  from posthistory ph
  left join closereasontypes crt on (ph.comment ~ '^[0-9]+$' and cast(ph.comment as integer) = crt.id)
  group by ph.postid
),
rolling_user_engagement as (
  select pa.user_id,
         date_trunc('month', pa.creationdate) as month_bucket,
         count(*) filter (where pa.posttypeid = 1) as q_in_month,
         count(*) filter (where pa.posttypeid = 2) as a_in_month,
         sum(pa.net_votes) as net_votes_in_month
  from post_activity pa
  group by pa.user_id, date_trunc('month', pa.creationdate)
),
engagement_windows as (
  select rue.user_id,
         rue.month_bucket,
         sum(q_in_month) over (partition by rue.user_id order by rue.month_bucket rows between 2 preceding and current row) as q_last_3mo,
         sum(a_in_month) over (partition by rue.user_id order by rue.month_bucket rows between 2 preceding and current row) as a_last_3mo,
         sum(net_votes_in_month) over (partition by rue.user_id order by rue.month_bucket rows between 5 preceding and current row) as net_votes_last_6mo
  from rolling_user_engagement rue
),
post_edit_bursts as (
  select ph.postid,
         count(*) filter (where ph.posthistorytypeid in (4,5,6,7,8,9,24)) as edits,
         count(*) filter (where ph.posthistorytypeid in (10,11,12,13)) as mod_actions,
         min(ph.creationdate) as first_hist,
         max(ph.creationdate) as last_hist,
         max(ph.creationdate) - min(ph.creationdate) as hist_span
  from posthistory ph
  group by ph.postid
),
quality_flag as (
  select pa.post_id,
         case
           when pa.posttypeid = 1 and coalesce(pa.upvotes,0) >= 5 and coalesce(pa.net_votes,0) >= 3 and pa.has_accepted = 1 then 'great_q'
           when pa.posttypeid = 2 and coalesce(pa.upvotes,0) >= 3 and coalesce(pa.net_votes,0) >= 2 then 'solid_a'
           when coalesce(pa.downvotes,0) > coalesce(pa.upvotes,0) and coalesce(pa.viewcount,0) > 50 then 'controversial'
           when pa.tag_count is not null and pa.tag_count >= 5 then 'broadly_tagged'
           else 'normal'
         end as quality_bucket
  from post_activity pa
),
user_peer_interactions as (
  select ru.user_id,
         count(distinct cm.commenter_id) as unique_commenters_on_posts,
         sum(cm.comment_count) as total_comments_on_posts
  from recent_users ru
  left join posts p on p.owneruserid = ru.user_id
  left join commenters cm on cm.postid = p.id
  group by ru.user_id
),
user_post_ranks as (
  select pa.user_id,
         pa.post_id,
         pa.posttypeid,
         pa.net_votes,
         dense_rank() over (partition by pa.user_id, pa.posttypeid order by pa.net_votes desc nulls last, pa.viewcount desc nulls last, pa.creationdate) as rank_by_net_votes
  from post_activity pa
),
top_posts as (
  select upr.user_id,
         max(case when upr.posttypeid = 1 and upr.rank_by_net_votes = 1 then upr.post_id end) as top_question_id,
         max(case when upr.posttypeid = 2 and upr.rank_by_net_votes = 1 then upr.post_id end) as top_answer_id
  from user_post_ranks upr
  group by upr.user_id
),
tag_extract as (
  select p.id as post_id,
         unnest(string_to_array(coalesce(nullif(substring(p.tags, 2, greatest(length(p.tags)-2,0)), ''), ''), '><')) as tagname
  from posts p
  where p.posttypeid = 1 and p.tags is not null
),
user_top_tags as (
  select qa.owneruserid as user_id,
         te.tagname,
         count(*) as cnt,
         row_number() over (partition by qa.owneruserid order by count(*) desc, min(qa.creationdate)) as rn
  from q_and_a qa
  join tag_extract te on te.post_id = qa.id
  group by qa.owneruserid, te.tagname
),
user_summary as (
  select ru.user_id,
         ru.displayname,
         ru.reputation,
         ru.location,
         ru.website_host,
         up.q_count,
         up.a_count,
         up.total_score,
         up.avg_score,
         up.max_score,
         up.min_score,
         up.active_days,
         coalesce(ub.badges_total,0) as badges_total,
         coalesce(ub.gold,0) as gold,
         coalesce(ub.silver,0) as silver,
         coalesce(ub.bronze,0) as bronze,
         coalesce(ub.tag_badges,0) as tag_badges,
         coalesce(upi.unique_commenters_on_posts,0) as unique_commenters_on_posts,
         coalesce(upi.total_comments_on_posts,0) as total_comments_on_posts
  from recent_users ru
  left join user_posts up on up.user_id = ru.user_id
  left join user_badges ub on ub.userid = ru.user_id
  left join user_peer_interactions upi on upi.user_id = ru.user_id
)
select us.user_id,
       us.displayname,
       us.reputation,
       us.location,
       us.website_host,
       us.q_count,
       us.a_count,
       us.total_score,
       us.avg_score,
       us.max_score,
       us.min_score,
       us.active_days,
       us.badges_total,
       us.gold,
       us.silver,
       us.bronze,
       us.tag_badges,
       us.unique_commenters_on_posts,
       us.total_comments_on_posts,
       tp.top_question_id,
       tp.top_answer_id,
       et.q_last_3mo,
       et.a_last_3mo,
       et.net_votes_last_6mo,
       t1.tagname as top_tag_1,
       t2.tagname as top_tag_2,
       t3.tagname as top_tag_3,
       coalesce(sum(case when qf.quality_bucket in ('great_q','solid_a') then 1 else 0 end),0) as high_quality_posts,
       coalesce(sum(case when qf.quality_bucket = 'controversial' then 1 else 0 end),0) as controversial_posts,
       coalesce(avg(pa.viewcount),0) as avg_views,
       coalesce(avg(pa.net_votes),0) as avg_net_votes,
       coalesce(max(pa.score),0) as best_score,
       coalesce(sum(case when cr.closed_at is not null then 1 else 0 end),0) as closed_posts,
       coalesce(sum(coalesce(dc.dup_count,0)),0) as duplicates_as_canonical,
       coalesce(sum(peb.edits),0) as total_edits,
       coalesce(sum(peb.mod_actions),0) as total_mod_actions,
       coalesce(max(peb.hist_span), interval '0 seconds') as max_hist_span
from user_summary us
left join top_posts tp on tp.user_id = us.user_id
left join engagement_windows et on et.user_id = us.user_id
left join post_activity pa on pa.user_id = us.user_id
left join quality_flag qf on qf.post_id = pa.post_id
left join closed_reasons cr on cr.postid = pa.post_id
left join dup_clusters dc on dc.canonical_id = pa.post_id
left join post_edit_bursts peb on peb.postid = pa.post_id
left join lateral (
  select tagname from user_top_tags utt where utt.user_id = us.user_id and utt.rn = 1
) t1 on true
left join lateral (
  select tagname from user_top_tags utt where utt.user_id = us.user_id and utt.rn = 2
) t2 on true
left join lateral (
  select tagname from user_top_tags utt where utt.user_id = us.user_id and utt.rn = 3
) t3 on true
where (us.q_count + us.a_count) > 0
group by us.user_id, us.displayname, us.reputation, us.location, us.website_host,
         us.q_count, us.a_count, us.total_score, us.avg_score, us.max_score, us.min_score,
         us.active_days, us.badges_total, us.gold, us.silver, us.bronze, us.tag_badges,
         us.unique_commenters_on_posts, us.total_comments_on_posts,
         tp.top_question_id, tp.top_answer_id, et.q_last_3mo, et.a_last_3mo, et.net_votes_last_6mo,
         t1.tagname, t2.tagname, t3.tagname
having coalesce(sum(pa.net_votes),0) >= -10
order by us.reputation desc, coalesce(sum(pa.net_votes),0) desc
limit 250;