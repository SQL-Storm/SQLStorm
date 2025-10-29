-- {"query": "80.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3226}
with recent_users as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    u.creationdate,
    u.location,
    u.websiteurl,
    coalesce(nullif(trim(u.location), ''), 'Unknown') as norm_location,
    date_trunc('month', u.creationdate) as cohort_month,
    row_number() over (order by u.creationdate desc, u.id desc) as rn_global_newest
  from users u
),
post_activity as (
  select
    p.id as post_id,
    p.posttypeid,
    p.owneruserid,
    p.score,
    p.viewcount,
    p.creationdate,
    p.lastactivitydate,
    p.answercount,
    p.commentcount,
    p.favoritecount,
    p.closeddate,
    p.title,
    p.tags,
    case when p.posttypeid = 1 then 'Question'
         when p.posttypeid = 2 then 'Answer'
         else 'Other' end as posttype_name,
    case when p.tags is null then 0
         when length(p.tags) <= 2 then 0
         else array_length(string_to_array(substring(p.tags, 2, length(p.tags)-2), '><'), 1) end as tag_count
  from posts p
),
user_agg as (
  select
    ra.user_id,
    count(*) filter (where pa.posttypeid = 1) as q_count,
    count(*) filter (where pa.posttypeid = 2) as a_count,
    sum(pa.score) as total_score,
    avg(nullif(pa.score,0)) as avg_nonzero_score,
    max(pa.viewcount) as max_views,
    sum(case when pa.closeddate is not null then 1 else 0 end) as closed_posts,
    min(pa.creationdate) as first_post_at,
    max(pa.lastactivitydate) as last_activity_at,
    percentile_cont(0.5) within group (order by pa.score) as median_score
  from recent_users ra
  left join post_activity pa
    on pa.owneruserid = ra.user_id
  group by ra.user_id
),
badge_classes as (
  select
    b.userid as user_id,
    sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
    sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
    sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
    sum(case when b.tagbased = true then 1 else 0 end) as tag_badges,
    min(b.date) as first_badge_at,
    max(b.date) as last_badge_at
  from badges b
  group by b.userid
),
votes_by_type as (
  select
    v.userid as user_id,
    count(*) filter (where v.votetypeid = 2) as upvotes_cast,
    count(*) filter (where v.votetypeid = 3) as downvotes_cast,
    count(*) filter (where v.votetypeid = 5) as favorites_cast,
    count(*) filter (where v.votetypeid in (8,9)) as bounties_events,
    sum(coalesce(v.bountyamount,0)) filter (where v.votetypeid = 8) as bounty_started_amount,
    sum(coalesce(v.bountyamount,0)) filter (where v.votetypeid = 9) as bounty_awarded_amount
  from votes v
  group by v.userid
),
comments_stats as (
  select
    c.userid as user_id,
    count(*) as comment_count,
    sum(coalesce(c.score,0)) as comment_score_sum,
    max(c.creationdate) as last_comment_at,
    avg(length(c.text)) as avg_comment_length
  from comments c
  group by c.userid
),
dup_links as (
  select
    pl.postid as duplicate_post_id,
    pl.relatedpostid as original_post_id,
    min(pl.creationdate) as first_dup_link_at
  from postlinks pl
  where pl.linktypeid = 3
  group by pl.postid, pl.relatedpostid
),
post_closures as (
  select
    ph.postid,
    min(ph.creationdate) filter (where ph.posthistorytypeid = 10) as first_close_at,
    max(ph.creationdate) filter (where ph.posthistorytypeid = 11) as last_reopen_at,
    max(
      case
        when ph.posthistorytypeid = 10
             and ph.comment ~ '^[0-9]+$'
        then cast(ph.comment as integer)
        else null
      end
    ) as close_reason_id_any
  from posthistory ph
  where ph.posthistorytypeid in (10,11)
  group by ph.postid
),
hot_questions as (
  select
    ph.postid,
    min(ph.creationdate) filter (where ph.posthistorytypeid = 52) as became_hot_at,
    max(ph.creationdate) filter (where ph.posthistorytypeid = 53) as removed_hot_at
  from posthistory ph
  where ph.posthistorytypeid in (52,53)
  group by ph.postid
),
activity_scores as (
  select
    pa.owneruserid as user_id,
    sum(
      case
        when pa.posttypeid = 1 then greatest(0, pa.score) * 5 + coalesce(pa.viewcount,0) / 100.0
        when pa.posttypeid = 2 then greatest(0, pa.score) * 3
        else 0
      end
    ) as content_points,
    sum(coalesce(pa.commentcount,0)) as total_comment_count_on_posts,
    sum(case when hc.became_hot_at is not null then 1 else 0 end) as hot_q_count,
    sum(case when pc.first_close_at is not null then 1 else 0 end) as closed_post_count,
    sum(case when dl.duplicate_post_id is not null then 1 else 0 end) as dup_marked_count
  from post_activity pa
  left join hot_questions hc on hc.postid = pa.post_id
  left join post_closures pc on pc.postid = pa.post_id
  left join dup_links dl on dl.duplicate_post_id = pa.post_id
  group by pa.owneruserid
),
user_ranked as (
  select
    ru.user_id,
    ru.displayname,
    ru.reputation,
    ru.creationdate,
    ru.location,
    ru.websiteurl,
    ru.norm_location,
    ru.cohort_month,
    ru.rn_global_newest,
    ua.q_count,
    ua.a_count,
    ua.total_score,
    ua.avg_nonzero_score,
    ua.max_views,
    ua.closed_posts,
    ua.first_post_at,
    ua.last_activity_at,
    ua.median_score,
    bc.gold_badges,
    bc.silver_badges,
    bc.bronze_badges,
    bc.tag_badges,
    bc.first_badge_at,
    bc.last_badge_at,
    vt.upvotes_cast,
    vt.downvotes_cast,
    vt.favorites_cast,
    vt.bounties_events,
    vt.bounty_started_amount,
    vt.bounty_awarded_amount,
    cs.comment_count,
    cs.comment_score_sum,
    cs.last_comment_at,
    cs.avg_comment_length,
    ascore.content_points,
    ascore.total_comment_count_on_posts,
    ascore.hot_q_count,
    ascore.closed_post_count,
    ascore.dup_marked_count,
    (
      coalesce(ua.total_score,0) * 2
      + coalesce(ua.a_count,0) * 1.5
      + coalesce(ua.q_count,0) * 1.0
      + coalesce(bc.gold_badges,0) * 20
      + coalesce(bc.silver_badges,0) * 10
      + coalesce(bc.bronze_badges,0) * 3
      + coalesce(vt.upvotes_cast,0) * 0.2
      - coalesce(vt.downvotes_cast,0) * 0.1
      + coalesce(ascore.content_points,0) * 0.5
      + coalesce(cs.comment_score_sum,0) * 0.3
      + coalesce(ascore.hot_q_count,0) * 15
      - coalesce(ascore.closed_post_count,0) * 5
      - coalesce(ascore.dup_marked_count,0) * 3
    ) as composite_activity_score
  from recent_users ru
  left join user_agg ua on ua.user_id = ru.user_id
  left join badge_classes bc on bc.user_id = ru.user_id
  left join votes_by_type vt on vt.user_id = ru.user_id
  left join comments_stats cs on cs.user_id = ru.user_id
  left join activity_scores ascore on ascore.user_id = ru.user_id
),
cohort_stats as (
  select
    cohort_month,
    count(*) as users_in_cohort,
    avg(coalesce(composite_activity_score,0)) as avg_cohort_score,
    percentile_cont(0.9) within group (order by coalesce(composite_activity_score,0)) as p90_cohort_score
  from user_ranked
  group by cohort_month
),
question_quality as (
  select
    pa.owneruserid as user_id,
    avg(pa.score) filter (where pa.posttypeid = 1) as avg_q_score,
    avg(pa.viewcount) filter (where pa.posttypeid = 1) as avg_q_views,
    avg(pa.tag_count) filter (where pa.posttypeid = 1) as avg_q_tag_count,
    sum(case when pc.close_reason_id_any in (101) then 1 else 0 end) as q_closed_as_duplicate,
    sum(case when hc.became_hot_at is not null then 1 else 0 end) as q_hot_count
  from post_activity pa
  left join post_closures pc on pc.postid = pa.post_id
  left join hot_questions hc on hc.postid = pa.post_id
  group by pa.owneruserid
),
answer_quality as (
  select
    pa.owneruserid as user_id,
    avg(pa.score) filter (where pa.posttypeid = 2) as avg_a_score,
    count(*) filter (where pa.posttypeid = 2 and pa.score > 0) as pos_answers,
    count(*) filter (where pa.posttypeid = 2 and pa.score <= 0) as nonpos_answers
  from post_activity pa
  group by pa.owneruserid
),
recent_hot_streak as (
  select
    pa.owneruserid as user_id,
    max(case when pa.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '30 days' and pa.score >= 5 then 1 else 0 end) as had_recent_good_post,
    count(*) filter (where pa.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '30 days' and pa.posttypeid = 2 and pa.score >= 2) as recent_good_answers
  from post_activity pa
  group by pa.owneruserid
),
location_norm as (
  select
    ru.user_id,
    upper(trim(split_part(ru.norm_location, ',', 1))) as country_guess
  from recent_users ru
),
final_scores as (
  select
    ur.user_id,
    ur.displayname,
    ur.reputation,
    ur.cohort_month,
    ur.norm_location,
    ur.rn_global_newest,
    ur.q_count,
    ur.a_count,
    ur.total_score,
    ur.avg_nonzero_score,
    ur.max_views,
    ur.closed_posts,
    ur.first_post_at,
    ur.last_activity_at,
    ur.median_score,
    ur.gold_badges,
    ur.silver_badges,
    ur.bronze_badges,
    ur.tag_badges,
    ur.first_badge_at,
    ur.last_badge_at,
    ur.upvotes_cast,
    ur.downvotes_cast,
    ur.favorites_cast,
    ur.bounties_events,
    ur.bounty_started_amount,
    ur.bounty_awarded_amount,
    ur.comment_count,
    ur.comment_score_sum,
    ur.last_comment_at,
    ur.avg_comment_length,
    ur.content_points,
    ur.total_comment_count_on_posts,
    ur.hot_q_count,
    ur.closed_post_count,
    ur.dup_marked_count,
    ur.composite_activity_score,
    qs.avg_q_score,
    qs.avg_q_views,
    qs.avg_q_tag_count,
    qs.q_closed_as_duplicate,
    qs.q_hot_count,
    aq.avg_a_score,
    aq.pos_answers,
    aq.nonpos_answers,
    rhs.had_recent_good_post,
    rhs.recent_good_answers,
    ln.country_guess,
    (ur.composite_activity_score - cs.avg_cohort_score) / nullif(cs.p90_cohort_score,0) as norm_score_in_cohort,
    dense_rank() over (order by ur.composite_activity_score desc nulls last, ur.user_id) as global_rank,
    dense_rank() over (partition by ur.cohort_month order by ur.composite_activity_score desc nulls last, ur.user_id) as cohort_rank
  from user_ranked ur
  left join question_quality qs on qs.user_id = ur.user_id
  left join answer_quality aq on aq.user_id = ur.user_id
  left join recent_hot_streak rhs on rhs.user_id = ur.user_id
  left join location_norm ln on ln.user_id = ur.user_id
  left join cohort_stats cs on cs.cohort_month = ur.cohort_month
)
select
  fs.user_id,
  fs.displayname,
  fs.reputation,
  fs.cohort_month,
  fs.country_guess,
  fs.q_count,
  fs.a_count,
  fs.gold_badges,
  fs.silver_badges,
  fs.bronze_badges,
  fs.upvotes_cast,
  fs.downvotes_cast,
  fs.comment_count,
  fs.total_score,
  fs.avg_nonzero_score,
  fs.median_score,
  fs.max_views,
  fs.hot_q_count,
  fs.closed_post_count,
  fs.dup_marked_count,
  fs.avg_q_score,
  fs.avg_q_views,
  fs.avg_q_tag_count,
  fs.q_closed_as_duplicate,
  fs.q_hot_count,
  fs.avg_a_score,
  fs.pos_answers,
  fs.nonpos_answers,
  fs.had_recent_good_post,
  fs.recent_good_answers,
  fs.first_post_at,
  fs.last_activity_at,
  fs.first_badge_at,
  fs.last_badge_at,
  fs.composite_activity_score,
  fs.norm_score_in_cohort,
  fs.global_rank,
  fs.cohort_rank,
  coalesce(fs.displayname, 'User#' || cast(fs.user_id as varchar)) || ' | Rep:' || cast(fs.reputation as varchar) ||
  ' | Q:' || cast(coalesce(fs.q_count,0) as varchar) || ' A:' || cast(coalesce(fs.a_count,0) as varchar) ||
  ' | Badges G/S/B:' || cast(coalesce(fs.gold_badges,0) as varchar) || '/' || cast(coalesce(fs.silver_badges,0) as varchar) || '/' || cast(coalesce(fs.bronze_badges,0) as varchar) ||
  ' | Score:' || cast(round(coalesce(fs.composite_activity_score,0),2) as varchar) as summary
from final_scores fs
where
  coalesce(fs.q_count,0) + coalesce(fs.a_count,0) + coalesce(fs.gold_badges,0) + coalesce(fs.silver_badges,0) + coalesce(fs.bronze_badges,0) > 0
  and (
    fs.global_rank <= 200
    or (fs.norm_score_in_cohort is not null and fs.norm_score_in_cohort >= 0.5)
    or (fs.had_recent_good_post = 1 and coalesce(fs.recent_good_answers,0) >= 3)
  )
order by fs.global_rank nulls last, fs.user_id
limit 500;