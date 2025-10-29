with recent_users as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    u.creationdate,
    u.location,
    coalesce(nullif(trim(u.websiteurl), ''), 'n/a') as websiteurl,
    date_trunc('month', u.creationdate) as cohort_month,
    row_number() over (order by u.creationdate desc, u.id desc) as rn_desc
  from users u
  where u.creationdate >= (select max(creationdate) - interval '730 days' from users)
),
user_activity as (
  select
    u.user_id,
    count(distinct p.id) filter (where p.posttypeid in (1,2)) as posts_authored,
    count(distinct c.id) as comments_authored,
    sum(coalesce(p.score,0)) as post_score_sum,
    sum(coalesce(c.score,0)) as comment_score_sum,
    sum(coalesce(p.viewcount,0)) as post_views_sum,
    sum(case when p.posttypeid = 1 and p.acceptedanswerid is not null then 1 else 0 end) as q_with_accepted_answer,
    max(greatest(coalesce(p.lastactivitydate, p.creationdate), coalesce(c.creationdate, timestamp '1970-01-01'))) as last_content_activity
  from recent_users u
  left join posts p on p.owneruserid = u.user_id
  left join comments c on c.userid = u.user_id
  group by u.user_id
),
badge_stats as (
  select
    b.userid as user_id,
    count(*) as badges_total,
    count(*) filter (where b.class = 1) as badges_gold,
    count(*) filter (where b.class = 2) as badges_silver,
    count(*) filter (where b.class = 3) as badges_bronze,
    count(*) filter (where b.tagbased = true) as badges_tagbased,
    min(b.date) as first_badge_date,
    max(b.date) as last_badge_date
  from badges b
  group by b.userid
),
vote_rollup as (
  select
    p.owneruserid as user_id,
    sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes_received,
    sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes_received,
    sum(case when v.votetypeid = 9 then coalesce(v.bountyamount,0) else 0 end) as bounty_awarded_total
  from posts p
  left join votes v on v.postid = p.id
  where p.owneruserid is not null
  group by p.owneruserid
),
tag_exposure as (
  select
    p.owneruserid as user_id,
    lower(trim(both '<>' from regexp_split_to_table(coalesce(p.tags,''), '><'))) as tagname
  from posts p
  where p.posttypeid = 1
),
top_tags as (
  select
    te.user_id,
    tt.tagname,
    count(*) as tag_q_count,
    dense_rank() over (partition by te.user_id order by count(*) desc, tt.tagname) as tag_rank
  from tag_exposure te
  join tags tt on tt.tagname = te.tagname
  group by te.user_id, tt.tagname
),
accepted_answer_latency as (
  select
    q.owneruserid as user_id,
    avg(extract(epoch from (a.creationdate - q.creationdate)) / 3600.0) as avg_hours_to_accept
  from posts q
  join posts a on a.id = q.acceptedanswerid
  where q.posttypeid = 1 and q.acceptedanswerid is not null
  group by q.owneruserid
),
edit_footprint as (
  select
    ph.userid as user_id,
    count(*) as edits_made,
    count(*) filter (where ph.posthistorytypeid in (4,5,6,7,8,9,24)) as content_edits,
    count(*) filter (where ph.posthistorytypeid in (10,11,12,13,14,15,19,20,35,36)) as mod_state_changes
  from posthistory ph
  where ph.userid is not null
  group by ph.userid
),
linked_duplicates as (
  select
    q.owneruserid as user_id,
    count(*) filter (where pl.linktypeid = 3) as dup_links_out,
    count(*) filter (where pl.linktypeid = 1) as links_out
  from postlinks pl
  join posts q on q.id = pl.postid and q.posttypeid = 1
  group by q.owneruserid
),
hot_streaks as (
  select
    p.owneruserid as user_id,
    count(*) filter (
      where p.posttypeid in (1,2)
        and p.score >= 5
        and p.creationdate >= (timestamp '2024-10-01 12:34:56') - interval '90 days'
    ) as recent_hot_posts,
    max(p.score) as max_post_score,
    percentile_cont(0.5) within group (order by coalesce(p.score,0)) as median_post_score
  from posts p
  where p.owneruserid is not null
  group by p.owneruserid
),
activity_calendar as (
  select
    u.user_id,
    date_trunc('day', p.creationdate) as day,
    count(*) filter (where p.posttypeid = 1) as q_count,
    count(*) filter (where p.posttypeid = 2) as a_count,
    count(c.id) as comment_count
  from recent_users u
  left join posts p on p.owneruserid = u.user_id
  left join comments c on c.userid = u.user_id and date_trunc('day', c.creationdate) = date_trunc('day', p.creationdate)
  group by u.user_id, date_trunc('day', p.creationdate)
),
burstiness as (
  select
    ac.user_id,
    coalesce(stddev_pop(coalesce(ac.q_count,0) + coalesce(ac.a_count,0) + coalesce(ac.comment_count,0)),0) as activity_stddev,
    coalesce(avg(coalesce(ac.q_count,0) + coalesce(ac.a_count,0) + coalesce(ac.comment_count,0)),0) as activity_avg
  from activity_calendar ac
  group by ac.user_id
),
recent_duplicate_closures as (
  select
    ph.postid,
    ph.creationdate as close_date,
    cast(nullif(ph.comment,'') as integer) as close_reason_id
  from posthistory ph
  where ph.posthistorytypeid = 10
    and ph.creationdate >= (timestamp '2024-10-01 12:34:56') - interval '365 days'
),
dup_impact as (
  select
    p.owneruserid as user_id,
    count(*) filter (where rdc.close_reason_id = 101) as duplicates_closed_last_year
  from recent_duplicate_closures rdc
  join posts p on p.id = rdc.postid
  group by p.owneruserid
),
user_quality as (
  select
    ua.user_id,
    case
      when coalesce(ua.posts_authored,0) + coalesce(ua.comments_authored,0) = 0 then null
      else round(
        (
          0.4 * coalesce(ua.post_score_sum,0)
          + 0.2 * coalesce(ua.comment_score_sum,0)
          + 0.1 * coalesce(vr.upvotes_received,0)
          - 0.1 * coalesce(vr.downvotes_received,0)
          + 0.2 * coalesce(vr.bounty_awarded_total,0) / nullif(coalesce(ua.posts_authored,0),0)
        ) , 2
      )
    end as quality_score
  from user_activity ua
  left join vote_rollup vr on vr.user_id = ua.user_id
)
select
  ru.user_id,
  ru.displayname,
  ru.reputation,
  ru.cohort_month,
  ru.location,
  ru.websiteurl,
  ua.posts_authored,
  ua.comments_authored,
  ua.post_score_sum,
  ua.comment_score_sum,
  ua.post_views_sum,
  ua.q_with_accepted_answer,
  ua.last_content_activity,
  bs.badges_total,
  bs.badges_gold,
  bs.badges_silver,
  bs.badges_bronze,
  bs.badges_tagbased,
  bs.first_badge_date,
  bs.last_badge_date,
  vr.upvotes_received,
  vr.downvotes_received,
  vr.bounty_awarded_total,
  ha.avg_hours_to_accept,
  ef.edits_made,
  ef.content_edits,
  ef.mod_state_changes,
  ld.dup_links_out,
  ld.links_out,
  hs.recent_hot_posts,
  hs.max_post_score,
  hs.median_post_score,
  dr.duplicates_closed_last_year,
  b.activity_stddev,
  b.activity_avg,
  uq.quality_score,
  (select array_agg(label) from (
     values
       (case when coalesce(ua.posts_authored,0) = 0 then 'no_posts' end),
       (case when coalesce(ua.comments_authored,0) = 0 then 'no_comments' end),
       (case when coalesce(bs.badges_total,0) = 0 then 'no_badges' end),
       (case when coalesce(vr.upvotes_received,0) - coalesce(vr.downvotes_received,0) < 0 then 'net_negative_votes' end),
       (case when coalesce(hs.recent_hot_posts,0) > 5 then 'hot_streak' end),
       (case when coalesce(dr.duplicates_closed_last_year,0) > 2 then 'dupe_prone' end)
  ) as t(label) where label is not null) as flags,
  string_agg(tt.tagname, ', ' order by tt.tagname) filter (where tt.tag_rank <= 3) as top_3_tags,
  case
    when ru.reputation >= 100000 then 'legend'
    when ru.reputation >= 50000 then 'veteran'
    when ru.reputation >= 10000 then 'expert'
    when ru.reputation >= 2000 then 'regular'
    when ru.reputation is null then 'unknown'
    else 'newbie'
  end as rep_bucket
from recent_users ru
left join user_activity ua on ua.user_id = ru.user_id
left join badge_stats bs on bs.user_id = ru.user_id
left join vote_rollup vr on vr.user_id = ru.user_id
left join accepted_answer_latency ha on ha.user_id = ru.user_id
left join edit_footprint ef on ef.user_id = ru.user_id
left join linked_duplicates ld on ld.user_id = ru.user_id
left join hot_streaks hs on hs.user_id = ru.user_id
left join dup_impact dr on dr.user_id = ru.user_id
left join burstiness b on b.user_id = ru.user_id
left join user_quality uq on uq.user_id = ru.user_id
left join top_tags tt on tt.user_id = ru.user_id and tt.tag_rank <= 5
where
  (ru.rn_desc <= 5000 or coalesce(ua.posts_authored,0) > 0)
  and (
    ru.location is null
    or lower(ru.location) like '%united%'
    or lower(ru.location) like '%india%'
    or lower(ru.location) like '%europe%'
  )
group by
  ru.user_id, ru.displayname, ru.reputation, ru.cohort_month, ru.location, ru.websiteurl,
  ua.posts_authored, ua.comments_authored, ua.post_score_sum, ua.comment_score_sum, ua.post_views_sum,
  ua.q_with_accepted_answer, ua.last_content_activity,
  bs.badges_total, bs.badges_gold, bs.badges_silver, bs.badges_bronze, bs.badges_tagbased, bs.first_badge_date, bs.last_badge_date,
  vr.upvotes_received, vr.downvotes_received, vr.bounty_awarded_total,
  ha.avg_hours_to_accept,
  ef.edits_made, ef.content_edits, ef.mod_state_changes,
  ld.dup_links_out, ld.links_out,
  hs.recent_hot_posts, hs.max_post_score, hs.median_post_score,
  dr.duplicates_closed_last_year,
  b.activity_stddev, b.activity_avg,
  uq.quality_score
having
  coalesce(ua.posts_authored,0) + coalesce(ua.comments_authored,0) + coalesce(bs.badges_total,0) > 0
order by
  coalesce(uq.quality_score, -1) desc,
  coalesce(vr.upvotes_received,0) - coalesce(vr.downvotes_received,0) desc,
  ru.reputation desc,
  ru.user_id
limit 1000;