with
recent_users as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    u.creationdate,
    u.lastaccessdate,
    u.location,
    u.websiteurl,
    coalesce(nullif(trim(u.profileimageurl), ''), 'no-image') as profile_image_url,
    row_number() over (order by u.lastaccessdate desc, u.reputation desc) as rn_recent,
    dense_rank() over (partition by coalesce(nullif(u.location, ''), 'unknown') order by u.reputation desc) as dr_loc_rep
  from users u
  where u.reputation > 0
    and u.lastaccessdate >= (select max(lastaccessdate) - interval '90 days' from users)
),
recent_posts as (
  select
    p.id as post_id,
    p.posttypeid,
    p.owneruserid,
    p.creationdate,
    p.score,
    p.viewcount,
    p.answercount,
    p.commentcount,
    p.favoritecount,
    p.closeddate,
    p.title,
    p.tags,
    -- convert tags like '<a><b>' into rows later using splitting in post_tags
    case
      when p.posttypeid = 1 then 'Question'
      when p.posttypeid = 2 then 'Answer'
      else 'Other'
    end as post_kind
  from posts p
  where p.creationdate >= (select coalesce(max(creationdate), timestamp '2024-10-01 12:34:56') - interval '365 days' from posts)
),
post_votes as (
  select
    v.postid,
    count(case when v.votetypeid = 2 then 1 end) as upvotes,
    count(case when v.votetypeid = 3 then 1 end) as downvotes,
    count(case when v.votetypeid in (8,9) then 1 end) as bounty_votes,
    sum(coalesce(v.bountyamount,0)) as bounty_total,
    min(v.creationdate) as first_vote_at,
    max(v.creationdate) as last_vote_at
  from votes v
  where v.creationdate >= (select coalesce(max(creationdate), timestamp '2024-10-01 12:34:56') - interval '365 days' from votes)
  group by v.postid
),
post_comments as (
  select
    c.postid,
    count(*) as comment_count,
    avg(coalesce(nullif(length(c.text),0), 0)) as avg_comment_length,
    min(c.creationdate) as first_comment_at,
    max(c.creationdate) as last_comment_at
  from comments c
  where c.creationdate >= (select coalesce(max(creationdate), timestamp '2024-10-01 12:34:56') - interval '365 days' from comments)
  group by c.postid
),
user_badges as (
  select
    b.userid,
    count(*) as total_badges,
    count(case when b.class = 1 then 1 end) as gold_badges,
    count(case when b.class = 2 then 1 end) as silver_badges,
    count(case when b.class = 3 then 1 end) as bronze_badges,
    min(b.date) as first_badge_date,
    max(b.date) as last_badge_date,
    max(case when b.class = 1 then b.name end) as sample_gold_name
  from badges b
  group by b.userid
),
post_links_agg as (
  select
    pl.postid,
    count(case when pl.linktypeid = 3 then 1 end) as duplicate_of_count,
    count(case when pl.linktypeid = 1 then 1 end) as linked_count,
    count(distinct case when pl.linktypeid = 3 then pl.relatedpostid end) as distinct_dupe_targets
  from postlinks pl
  where pl.creationdate >= (select coalesce(max(creationdate), timestamp '2024-10-01 12:34:56') - interval '365 days' from postlinks)
  group by pl.postid
),
post_closures as (
  select
    ph.postid,
    max(ph.creationdate) as last_closed_at,
    max(case when ph.posthistorytypeid = 10 then ph.comment end) as last_close_reason_id,
    count(case when ph.posthistorytypeid = 10 then 1 end) as close_events,
    count(case when ph.posthistorytypeid = 11 then 1 end) as reopen_events
  from posthistory ph
  where ph.posthistorytypeid in (10,11)
  group by ph.postid
),
tag_popularity as (
  select
    t.tagname,
    t.count as tag_total_count,
    coalesce(nullif(t.tagname, ''), 'unknown') as tag_key
  from tags t
),
post_tags as (
  -- Split tags text into rows in a portable way: remove leading/trailing <> then split on '><'
  select
    rp.post_id,
    lower(trim(tag)) as tagname
  from recent_posts rp,
  lateral (
    select regexp_split_to_table(
      case
        when rp.tags is null then ''
        when left(rp.tags,1) = '<' and right(rp.tags,1) = '>' then substring(rp.tags from 2 for char_length(rp.tags)-2)
        else rp.tags
      end,
      '><'
    ) as tag
  ) s
  where rp.tags is not null and rp.tags <> ''
),
post_tag_metrics as (
  select
    pt.post_id,
    count(*) as tag_count,
    avg(tp.tag_total_count) as avg_tag_popularity,
    max(tp.tag_total_count) as max_tag_popularity,
    sum(case when tp.tag_total_count is null then 1 else 0 end) as unknown_tag_hits
  from post_tags pt
  left join tag_popularity tp
    on tp.tagname = pt.tagname
  group by pt.post_id
),
user_activity as (
  select
    u.id as user_id,
    coalesce((
      select count(*) from posts p
      where p.owneruserid = u.id
        and p.creationdate >= u.creationdate
    ), 0) as lifetime_posts,
    coalesce((
      select count(*) from comments c where c.userid = u.id
    ), 0) as lifetime_comments,
    coalesce((
      select sum(case when v.votetypeid = 2 then 1 when v.votetypeid = 3 then -1 else 0 end)
      from votes v
      join posts p on p.id = v.postid
      where p.owneruserid = u.id
    ), 0) as net_votes_received
  from users u
),
post_agg as (
  select
    rp.post_id,
    rp.posttypeid,
    rp.owneruserid,
    rp.creationdate,
    rp.score,
    rp.viewcount,
    rp.answercount,
    rp.commentcount,
    rp.favoritecount,
    rp.closeddate,
    rp.title,
    rp.post_kind,
    coalesce(pv.upvotes, 0) as upvotes,
    coalesce(pv.downvotes, 0) as downvotes,
    coalesce(pv.bounty_votes, 0) as bounty_votes,
    coalesce(pv.bounty_total, 0) as bounty_total,
    coalesce(pc.comment_count, 0) as dynamic_comment_count,
    pc.avg_comment_length,
    pla.duplicate_of_count,
    pla.linked_count,
    pla.distinct_dupe_targets,
    pcl.last_closed_at,
    pcl.last_close_reason_id,
    pcl.close_events,
    pcl.reopen_events,
    ptm.tag_count,
    ptm.avg_tag_popularity,
    ptm.max_tag_popularity,
    ptm.unknown_tag_hits,
    (coalesce(rp.score,0)*2
     + coalesce(pv.upvotes,0)
     - coalesce(pv.downvotes,0)
     + coalesce(pv.bounty_votes,0)
     + least(coalesce(rp.viewcount,0)/100, 50)
     + coalesce(pc.comment_count,0)/5.0
     + coalesce(rp.answercount,0)
     - coalesce(pla.duplicate_of_count,0)*2
     ) as engagement_score
  from recent_posts rp
  left join post_votes pv on pv.postid = rp.post_id
  left join post_comments pc on pc.postid = rp.post_id
  left join post_links_agg pla on pla.postid = rp.post_id
  left join post_closures pcl on pcl.postid = rp.post_id
  left join post_tag_metrics ptm on ptm.post_id = rp.post_id
),
ranked_posts as (
  select
    pa.post_id,
    pa.posttypeid,
    pa.owneruserid,
    pa.creationdate,
    pa.score,
    pa.viewcount,
    pa.answercount,
    pa.commentcount,
    pa.favoritecount,
    pa.closeddate,
    pa.title,
    pa.post_kind,
    pa.upvotes,
    pa.downvotes,
    pa.bounty_votes,
    pa.bounty_total,
    pa.dynamic_comment_count,
    pa.avg_comment_length,
    pa.duplicate_of_count,
    pa.linked_count,
    pa.distinct_dupe_targets,
    pa.last_closed_at,
    pa.last_close_reason_id,
    pa.close_events,
    pa.reopen_events,
    pa.tag_count,
    pa.avg_tag_popularity,
    pa.max_tag_popularity,
    pa.unknown_tag_hits,
    pa.engagement_score,
    row_number() over (partition by pa.owneruserid order by pa.engagement_score desc, pa.creationdate desc, pa.post_id desc) as rn_owner_top,
    ntile(10) over (order by pa.engagement_score desc nulls last) as engagement_decile
  from post_agg pa
),
global_stats as (
  select percentile_disc(0.5) within group (order by coalesce(viewcount,0)) as global_median_views
  from post_agg
),
user_rollup as (
  select
    ru.user_id,
    ru.displayname,
    ru.reputation,
    ru.creationdate,
    ru.lastaccessdate,
    ru.location,
    ru.websiteurl,
    ru.profile_image_url,
    ru.rn_recent,
    ru.dr_loc_rep,
    ub.total_badges,
    ub.gold_badges,
    ub.silver_badges,
    ub.bronze_badges,
    ua.lifetime_posts,
    ua.lifetime_comments,
    ua.net_votes_received,
    coalesce(sum(case when rp.post_kind = 'Question' then 1 else 0 end), 0) as questions_last_year,
    coalesce(sum(case when rp.post_kind = 'Answer' then 1 else 0 end), 0) as answers_last_year,
    coalesce(avg(rp.engagement_score), 0) as avg_engagement_last_year,
    max(rp.engagement_score) as max_engagement_last_year,
    count(distinct case when rp.engagement_decile <= 2 then rp.post_id end) as top_decile_posts
  from recent_users ru
  left join user_badges ub on ub.userid = ru.user_id
  left join user_activity ua on ua.user_id = ru.user_id
  left join ranked_posts rp on rp.owneruserid = ru.user_id
  group by
    ru.user_id, ru.displayname, ru.reputation, ru.creationdate, ru.lastaccessdate,
    ru.location, ru.websiteurl, ru.profile_image_url, ru.rn_recent, ru.dr_loc_rep,
    ub.total_badges, ub.gold_badges, ub.silver_badges, ub.bronze_badges,
    ua.lifetime_posts, ua.lifetime_comments, ua.net_votes_received
),
best_post_per_user as (
  select
    rp.owneruserid as user_id,
    rp.post_id,
    rp.title,
    rp.post_kind,
    rp.creationdate,
    rp.engagement_score,
    rp.score,
    rp.viewcount,
    rp.answercount,
    rp.commentcount,
    rp.duplicate_of_count,
    row_number() over (
      partition by rp.owneruserid
      order by (case when coalesce(rp.duplicate_of_count,0)=0 then 1 else 0 end) desc,
               rp.engagement_score desc,
               rp.creationdate desc,
               rp.post_id desc
    ) as rn
  from ranked_posts rp
)
select
  ur.user_id,
  ur.displayname,
  ur.reputation,
  ur.location,
  ur.websiteurl,
  ur.profile_image_url,
  ur.rn_recent,
  ur.dr_loc_rep,
  coalesce(ur.total_badges, 0) as total_badges,
  coalesce(ur.gold_badges, 0) as gold_badges,
  coalesce(ur.silver_badges, 0) as silver_badges,
  coalesce(ur.bronze_badges, 0) as bronze_badges,
  ur.lifetime_posts,
  ur.lifetime_comments,
  ur.net_votes_received,
  ur.questions_last_year,
  ur.answers_last_year,
  coalesce(ur.avg_engagement_last_year, 0) as avg_engagement_last_year,
  ur.max_engagement_last_year,
  ur.top_decile_posts,
  bp.post_id as best_post_id,
  coalesce(bp.title, '(no title)') as best_post_title,
  bp.post_kind as best_post_kind,
  bp.creationdate as best_post_created,
  bp.engagement_score as best_post_engagement,
  bp.score as best_post_score,
  bp.viewcount as best_post_views,
  bp.answercount as best_post_answers,
  bp.commentcount as best_post_comments,
  bp.duplicate_of_count as best_post_dupe_links,
  case
    when ur.reputation >= 10000 and coalesce(ur.gold_badges,0) >= 5 and coalesce(ur.avg_engagement_last_year,0) >= 50 then 'elite'
    when ur.reputation >= 2000 and (coalesce(ur.silver_badges,0) + coalesce(ur.gold_badges,0)) >= 3 and ur.top_decile_posts >= 2 then 'rising'
    when ur.lifetime_posts = 0 and ur.lifetime_comments > 0 then 'commenter'
    when ur.questions_last_year > 0 and ur.answers_last_year = 0 then 'asker'
    when ur.answers_last_year > 0 and ur.questions_last_year = 0 then 'answerer'
    else 'mixed'
  end as contributor_tier,
  gs.global_median_views
from user_rollup ur
left join best_post_per_user bp
  on bp.user_id = ur.user_id
 and bp.rn = 1
cross join global_stats gs
where
  (
    ur.reputation >= (select percentile_disc(0.9) within group (order by reputation) from users)
    or ur.reputation <= (select percentile_disc(0.1) within group (order by reputation) from users)
    or ur.rn_recent <= 200
  )
  and coalesce(ur.avg_engagement_last_year, 0) is not null
order by
  contributor_tier asc,
  ur.rn_recent asc,
  ur.reputation desc,
  ur.user_id asc
limit 500;