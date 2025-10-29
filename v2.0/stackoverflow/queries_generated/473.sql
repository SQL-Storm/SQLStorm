-- {"query": "473.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3324} 
with recent_users as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    u.creationdate,
    u.location,
    coalesce(nullif(trim(u.websiteurl), ''), 'n/a') as websiteurl,
    row_number() over (order by u.creationdate desc, u.id desc) as rn
  from users u
  where u.creationdate >= (select date_trunc('month', max(creationdate)) - interval '12 months' from users)
),
user_badge_rollup as (
  select
    b.userid,
    count(*) as total_badges,
    sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
    sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
    sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
    max(b.date) as last_badge_date
  from badges b
  group by b.userid
),
posts_enriched as (
  select
    p.id,
    p.posttypeid,
    p.owneruserid,
    p.creationdate,
    p.score,
    p.viewcount,
    p.title,
    p.tags,
    p.answercount,
    p.commentcount,
    p.favoritecount,
    p.closeddate,
    p.communityowneddate,
    p.contentlicense,
    coalesce(nullif(p.ownerdisplayname, ''), u.displayname) as effective_ownername,
    case
      when p.posttypeid = 1 then 'Question'
      when p.posttypeid = 2 then 'Answer'
      else 'Other'
    end as posttype_label,
    array_length(string_to_array(coalesce(substring(p.tags, 2, length(p.tags)-2), ''), '><'), 1) as tag_count,
    dense_rank() over (partition by p.posttypeid order by p.score desc nulls last) as score_rank_within_type
  from posts p
  left join users u on u.id = p.owneruserid
),
question_quality as (
  select
    q.id as question_id,
    q.owneruserid as owner_id,
    q.creationdate as question_created,
    q.score as question_score,
    q.viewcount as question_views,
    q.answercount,
    q.favoritecount,
    q.closeddate,
    q.tags,
    q.tag_count,
    -- weighted engagement metric
    (coalesce(q.viewcount,0) * 0.001 + coalesce(q.score,0) * 1.5 + coalesce(q.answercount,0) * 0.75 + coalesce(q.favoritecount,0) * 1.2) as engagement_score,
    -- time to accepted answer in hours (if any)
    (
      select extract(epoch from (pa.creationdate - q.creationdate))/3600.0
      from posts pa
      where pa.id = q.acceptedanswerid
    ) as hours_to_accept,
    -- number of duplicate links pointing to this question
    (
      select count(*) from postlinks pl
      where pl.linktypeid = 3 and pl.relatedpostid = q.id
    ) as duplicates_linked_here,
    -- number of times this question links to others
    (
      select count(*) from postlinks pl2
      where pl2.linktypeid in (1,3) and pl2.postid = q.id
    ) as outbound_links,
    -- comment sentiment proxy: sum of comment scores in first 7 days
    (
      select coalesce(sum(c.score),0)
      from comments c
      where c.postid = q.id
        and c.creationdate < q.creationdate + interval '7 days'
    ) as first_week_comment_score
  from posts_enriched q
  where q.posttypeid = 1
),
user_activity as (
  select
    u.id as user_id,
    count(*) filter (where p.posttypeid = 1) as questions_posted,
    count(*) filter (where p.posttypeid = 2) as answers_posted,
    sum(coalesce(p.score,0)) as total_post_score,
    sum(coalesce(p.viewcount,0)) as total_post_views,
    max(p.creationdate) as last_post_date
  from users u
  left join posts p on p.owneruserid = u.id
  group by u.id
),
tag_breakout as (
  select
    q.owner_id as user_id,
    lower(trim(t.tag)) as tag,
    count(*) as tag_q_count,
    sum(q.question_score) as tag_q_score,
    avg(q.engagement_score) as tag_engagement_avg
  from question_quality q
  cross join lateral unnest(string_to_array(coalesce(substring(q.tags, 2, length(q.tags)-2), ''), '><')) as t(tag)
  group by q.owner_id, lower(trim(t.tag))
),
top_tags_per_user as (
  select
    tb.user_id,
    tb.tag,
    tb.tag_q_count,
    tb.tag_q_score,
    tb.tag_engagement_avg,
    row_number() over (partition by tb.user_id order by tb.tag_q_count desc, tb.tag_q_score desc, tb.tag asc) as tag_rank
  from tag_breakout tb
),
post_history_flags as (
  select
    ph.postid,
    max(case when ph.posthistorytypeid in (10,35) then 1 else 0 end) as was_closed_or_migrated,
    max(case when ph.posthistorytypeid in (11) then 1 else 0 end) as was_reopened,
    max(case when ph.posthistorytypeid in (12,10) then 1 else 0 end) as was_deleted_or_closed,
    count(*) filter (where ph.posthistorytypeid in (24)) as suggested_edits_applied,
    max(ph.creationdate) filter (where ph.posthistorytypeid in (10,11,12,13,14,15,19,20,35)) as last_moderation_event
  from posthistory ph
  group by ph.postid
),
vote_rollup as (
  select
    v.postid,
    sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
    sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
    sum(case when v.votetypeid = 8 then coalesce(v.bountyamount,0) else 0 end) as bounty_started,
    sum(case when v.votetypeid = 9 then coalesce(v.bountyamount,0) else 0 end) as bounty_awarded,
    count(*) filter (where v.votetypeid in (10,11,12)) as mod_actions_votes
  from votes v
  group by v.postid
),
question_agg as (
  select
    q.question_id,
    q.owner_id,
    q.engagement_score,
    q.question_score,
    q.question_views,
    q.answercount,
    q.favoritecount,
    q.closeddate,
    q.tag_count,
    q.first_week_comment_score,
    coalesce(v.upvotes,0) as upvotes,
    coalesce(v.downvotes,0) as downvotes,
    coalesce(v.bounty_started,0) as bounty_started,
    coalesce(v.bounty_awarded,0) as bounty_awarded,
    ph.was_closed_or_migrated,
    ph.was_reopened,
    ph.was_deleted_or_closed,
    ph.suggested_edits_applied,
    ph.last_moderation_event,
    (coalesce(v.upvotes,0) - coalesce(v.downvotes,0)) as vote_delta
  from question_quality q
  left join vote_rollup v on v.postid = q.question_id
  left join post_history_flags ph on ph.postid = q.question_id
),
user_scores as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    ua.questions_posted,
    ua.answers_posted,
    ua.total_post_score,
    ua.total_post_views,
    coalesce(ubr.total_badges,0) as total_badges,
    coalesce(ubr.gold_badges,0) as gold_badges,
    coalesce(ubr.silver_badges,0) as silver_badges,
    coalesce(ubr.bronze_badges,0) as bronze_badges,
    ubr.last_badge_date,
    ua.last_post_date,
    count(distinct qa.question_id) as questions_considered,
    sum(qa.engagement_score) as sum_engagement,
    avg(qa.engagement_score) as avg_engagement,
    percentile_cont(0.5) within group (order by qa.engagement_score) as median_engagement,
    sum(qa.vote_delta) as sum_vote_delta,
    sum(case when qa.was_closed_or_migrated = 1 then 1 else 0 end) as closed_or_migrated_q,
    sum(case when qa.was_reopened = 1 then 1 else 0 end) as reopened_q,
    sum(qa.suggested_edits_applied) as total_suggested_edits_applied
  from users u
  left join user_activity ua on ua.user_id = u.id
  left join user_badge_rollup ubr on ubr.userid = u.id
  left join question_agg qa on qa.owner_id = u.id
  group by u.id, u.displayname, u.reputation, ua.questions_posted, ua.answers_posted, ua.total_post_score, ua.total_post_views, ubr.total_badges, ubr.gold_badges, ubr.silver_badges, ubr.bronze_badges, ubr.last_badge_date, ua.last_post_date
),
recent_user_window as (
  select
    rs.*,
    lag(rs.creationdate) over (order by rs.creationdate) as prev_user_created,
    lead(rs.creationdate) over (order by rs.creationdate) as next_user_created,
    sum(case when rs.location is null then 1 else 0 end) over () as null_location_users
  from recent_users rs
),
selected_users as (
  select
    us.user_id,
    us.displayname,
    us.reputation,
    us.questions_posted,
    us.answers_posted,
    us.total_post_score,
    us.total_post_views,
    us.total_badges,
    us.gold_badges,
    us.silver_badges,
    us.bronze_badges,
    us.last_badge_date,
    us.last_post_date,
    us.questions_considered,
    us.sum_engagement,
    us.avg_engagement,
    us.median_engagement,
    us.sum_vote_delta,
    us.closed_or_migrated_q,
    us.reopened_q,
    us.total_suggested_edits_applied,
    ru.creationdate as user_created,
    ru.location,
    ru.websiteurl,
    ru.rn as recent_user_rank,
    case when us.questions_posted is null and us.answers_posted is null then 1 else 0 end as no_posts_flag
  from user_scores us
  inner join recent_user_window ru on ru.user_id = us.user_id
  where coalesce(us.questions_considered, 0) + coalesce(us.answers_posted, 0) > 0
     or ru.rn <= 100
),
top3_tags as (
  select
    tpu.user_id,
    string_agg(tpu.tag, ', ' order by tpu.tag_rank) as top_3_tags
  from top_tags_per_user tpu
  where tpu.tag_rank <= 3
  group by tpu.user_id
),
user_quality_rank as (
  select
    su.*,
    coalesce(tt.top_3_tags, '(none)') as top_3_tags,
    rank() over (
      order by
        coalesce(su.avg_engagement, 0) desc,
        coalesce(su.sum_vote_delta, 0) desc,
        su.reputation desc,
        su.user_id asc
    ) as quality_rank_overall,
    rank() over (
      partition by case when su.location is null or trim(su.location) = '' then '(unknown)' else lower(su.location) end
      order by
        coalesce(su.avg_engagement, 0) desc,
        coalesce(su.sum_vote_delta, 0) desc,
        su.reputation desc,
        su.user_id asc
    ) as quality_rank_by_location
  from selected_users su
  left join top3_tags tt on tt.user_id = su.user_id
)
select
  uq.user_id,
  uq.displayname,
  uq.reputation,
  uq.user_created,
  uq.location,
  uq.websiteurl,
  uq.recent_user_rank,
  uq.questions_posted,
  uq.answers_posted,
  uq.total_post_score,
  uq.total_post_views,
  uq.total_badges,
  uq.gold_badges,
  uq.silver_badges,
  uq.bronze_badges,
  uq.last_badge_date,
  uq.last_post_date,
  uq.questions_considered,
  round(coalesce(uq.sum_engagement,0)::numeric, 2) as sum_engagement,
  round(coalesce(uq.avg_engagement,0)::numeric, 3) as avg_engagement,
  round(coalesce(uq.median_engagement,0)::numeric, 3) as median_engagement,
  uq.sum_vote_delta,
  uq.closed_or_migrated_q,
  uq.reopened_q,
  uq.total_suggested_edits_applied,
  uq.top_3_tags,
  uq.quality_rank_overall,
  uq.quality_rank_by_location,
  case
    when uq.avg_engagement is null then 'no-activity'
    when uq.avg_engagement >= (
      select percentile_cont(0.9) within group (order by coalesce(avg_engagement,0))
      from user_quality_rank
    ) then 'top-10%'
    when uq.avg_engagement >= (
      select percentile_cont(0.75) within group (order by coalesce(avg_engagement,0))
      from user_quality_rank
    ) then 'top-25%'
    when uq.avg_engagement >= (
      select percentile_cont(0.5) within group (order by coalesce(avg_engagement,0))
      from user_quality_rank
    ) then 'top-50%'
    else 'bottom-50%'
  end as engagement_bucket,
  -- elaborate predicate-driven flag
  case
    when uq.closed_or_migrated_q > 0 and uq.reopened_q = 0 then 'risky'
    when uq.closed_or_migrated_q > 0 and uq.reopened_q > 0 then 'controversial'
    when uq.answers_posted > uq.questions_posted then 'answerer'
    when uq.questions_posted > uq.answers_posted then 'asker'
    else 'balanced'
  end as author_profile_type
from user_quality_rank uq
where
  -- complicated filter mixing null and numeric logic
  (
    coalesce(uq.avg_engagement, -1) > (
      select avg(coalesce(avg_engagement,0)) + stddev_pop(coalesce(avg_engagement,0))
      from user_quality_rank
    )
    or uq.quality_rank_overall <= 200
    or (uq.recent_user_rank <= 50 and coalesce(uq.total_badges,0) >= 1)
  )
  and not (
    uq.no_posts_flag = 1
    and uq.recent_user_rank > 100
  )
order by
  uq.quality_rank_overall nulls last,
  uq.user_id
limit 500;