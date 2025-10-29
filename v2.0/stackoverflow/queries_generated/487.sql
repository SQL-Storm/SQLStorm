-- {"query": "487.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2961} 
with recent_users as (
  select u.id as user_id,
         u.displayname,
         u.reputation,
         u.creationdate,
         coalesce(nullif(trim(u.location), ''), 'Unknown') as location_norm,
         date_trunc('month', u.creationdate) as signup_month
  from users u
  where u.creationdate >= (select max(creationdate) - interval '365 days' from users)
),
user_activity as (
  select
    p.owneruserid as user_id,
    count(*) filter (where p.posttypeid = 1) as q_count,
    count(*) filter (where p.posttypeid = 2) as a_count,
    sum(coalesce(p.score,0)) as post_score_sum,
    sum(coalesce(p.viewcount,0)) as q_views_sum,
    count(distinct case when p.posttypeid = 1 then p.id end) as q_distinct,
    count(distinct case when p.posttypeid = 2 then p.id end) as a_distinct,
    max(p.lastactivitydate) as last_activity
  from posts p
  where p.owneruserid is not null
  group by p.owneruserid
),
user_comment_stats as (
  select
    c.userid as user_id,
    count(*) as comment_count,
    sum(coalesce(c.score,0)) as comment_score_sum,
    avg(nullif(c.score,0)) as avg_nonzero_comment_score,
    max(c.creationdate) as last_comment_date
  from comments c
  where c.userid is not null
  group by c.userid
),
user_badges as (
  select
    b.userid as user_id,
    count(*) as badge_count,
    count(*) filter (where b.class = 1) as gold_count,
    count(*) filter (where b.class = 2) as silver_count,
    count(*) filter (where b.class = 3) as bronze_count,
    max(b.date) as last_badge_date
  from badges b
  group by b.userid
),
question_metrics as (
  select
    p.owneruserid as user_id,
    sum(case when p.posttypeid = 1 and p.acceptedanswerid is not null then 1 else 0 end) as questions_with_accepted,
    avg(case when p.posttypeid = 1 then nullif(p.answercount,0)::numeric end) as avg_answers_per_q_nonzero,
    avg(case when p.posttypeid = 1 then p.score::numeric end) as avg_q_score,
    percentile_cont(0.9) within group (order by case when p.posttypeid = 1 then coalesce(p.viewcount,0) end) as p90_q_views
  from posts p
  where p.owneruserid is not null
  group by p.owneruserid
),
answer_metrics as (
  select
    p.owneruserid as user_id,
    sum(case when p.posttypeid = 2 and exists (select 1 from posts q where q.id = p.parentid and q.acceptedanswerid = p.id) then 1 else 0 end) as accepted_answers,
    avg(case when p.posttypeid = 2 then p.score::numeric end) as avg_a_score
  from posts p
  where p.owneruserid is not null
  group by p.owneruserid
),
dup_close_events as (
  select
    ph.postid,
    count(*) filter (where ph.posthistorytypeid in (10,35) and ph.comment in ('1','101')) as dup_close_count,
    min(ph.creationdate) filter (where ph.posthistorytypeid in (10,35) and ph.comment in ('1','101')) as first_dup_close_date
  from posthistory ph
  group by ph.postid
),
post_link_dups as (
  select pl.postid, count(*) filter (where pl.linktypeid = 3) as duplicate_links
  from postlinks pl
  group by pl.postid
),
post_flags_votes as (
  select v.postid,
         count(*) filter (where v.votetypeid in (12,4)) as spam_offensive_votes,
         count(*) filter (where v.votetypeid = 2) as upvotes,
         count(*) filter (where v.votetypeid = 3) as downvotes,
         sum(coalesce(v.bountyamount,0)) as bounty_total
  from votes v
  group by v.postid
),
post_scores as (
  select p.id,
         p.owneruserid as user_id,
         p.posttypeid,
         p.score,
         p.viewcount,
         coalesce(psv.upvotes,0) - coalesce(psv.downvotes,0) as net_votes,
         coalesce(psv.spam_offensive_votes,0) as flag_votes,
         coalesce(psv.bounty_total,0) as bounty_total,
         coalesce(dce.dup_close_count,0) as dup_close_count,
         coalesce(pld.duplicate_links,0) as duplicate_links
  from posts p
  left join post_flags_votes psv on psv.postid = p.id
  left join dup_close_events dce on dce.postid = p.id
  left join post_link_dups pld on pld.postid = p.id
),
user_post_rollup as (
  select
    ps.user_id,
    count(*) filter (where ps.posttypeid = 1) as q_total,
    count(*) filter (where ps.posttypeid = 2) as a_total,
    sum(case when ps.posttypeid = 1 then ps.viewcount else 0 end) as q_views_total,
    sum(ps.net_votes) as net_votes_total,
    sum(ps.flag_votes) as flag_votes_total,
    sum(ps.bounty_total) as bounty_total,
    sum(ps.dup_close_count) as dup_closes_total,
    sum(ps.duplicate_links) as dup_links_total
  from post_scores ps
  group by ps.user_id
),
tag_parse as (
  select
    p.id as post_id,
    p.owneruserid as user_id,
    unnest(string_to_array(substring(p.tags, 2, greatest(length(p.tags)-2,0)), '><')) as tag
  from posts p
  where p.posttypeid = 1 and p.tags is not null and p.owneruserid is not null
),
top_tags_per_user as (
  select user_id, tag, cnt, rn
  from (
    select tp.user_id, tp.tag, count(*) as cnt,
           row_number() over (partition by tp.user_id order by count(*) desc, tp.tag) as rn
    from tag_parse tp
    group by tp.user_id, tp.tag
  ) s
  where rn <= 3
),
top_tag_concat as (
  select user_id,
         string_agg(tag || ':' || cnt::text, ', ' order by rn) as top3_tags
  from top_tags_per_user
  group by user_id
),
user_windows as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    u.creationdate,
    sum(coalesce(p.score,0)) over (partition by u.id) as total_post_score_window,
    rank() over (order by u.reputation desc, u.id) as rep_rank_overall,
    dense_rank() over (partition by coalesce(nullif(trim(u.location), ''), 'Unknown') order by u.reputation desc) as rep_rank_by_location
  from users u
  left join posts p on p.owneruserid = u.id
),
activity_trend as (
  select
    p.owneruserid as user_id,
    date_trunc('month', p.creationdate) as month,
    count(*) as posts_in_month,
    avg(p.score)::numeric(18,4) as avg_score_in_month
  from posts p
  where p.owneruserid is not null
  group by p.owneruserid, date_trunc('month', p.creationdate)
),
activity_slope as (
  select
    a.user_id,
    case when count(*) >= 2
         then covar_samp(extract(epoch from a.month), posts_in_month) / nullif(var_samp(extract(epoch from a.month)),0)
         else null end as posts_per_second_slope,
    case when count(*) >= 2
         then covar_samp(extract(epoch from a.month), avg_score_in_month) / nullif(var_samp(extract(epoch from a.month)),0)
         else null end as avg_score_slope
  from activity_trend a
  group by a.user_id
),
normalized_user as (
  select
    u.user_id,
    u.displayname,
    u.reputation,
    u.creationdate,
    coalesce(nullif(trim(uu.location_norm), ''), 'Unknown') as location_norm
  from user_windows u
  left join recent_users uu on uu.user_id = u.user_id
),
final_users as (
  select
    n.user_id,
    n.displayname,
    n.reputation,
    n.creationdate,
    n.location_norm,
    ua.q_count,
    ua.a_count,
    ua.post_score_sum,
    ua.q_views_sum,
    ua.last_activity,
    ucs.comment_count,
    ucs.comment_score_sum,
    ucs.avg_nonzero_comment_score,
    ucs.last_comment_date,
    ub.badge_count,
    ub.gold_count,
    ub.silver_count,
    ub.bronze_count,
    ub.last_badge_date,
    qm.questions_with_accepted,
    qm.avg_answers_per_q_nonzero,
    qm.avg_q_score,
    qm.p90_q_views,
    am.accepted_answers,
    am.avg_a_score,
    upr.q_total,
    upr.a_total,
    upr.q_views_total,
    upr.net_votes_total,
    upr.flag_votes_total,
    upr.bounty_total,
    upr.dup_closes_total,
    upr.dup_links_total,
    ttc.top3_tags,
    uw.total_post_score_window,
    uw.rep_rank_overall,
    uw.rep_rank_by_location,
    ats.posts_per_second_slope,
    ats.avg_score_slope
  from normalized_user n
  left join user_activity ua on ua.user_id = n.user_id
  left join user_comment_stats ucs on ucs.user_id = n.user_id
  left join user_badges ub on ub.user_id = n.user_id
  left join question_metrics qm on qm.user_id = n.user_id
  left join answer_metrics am on am.user_id = n.user_id
  left join user_post_rollup upr on upr.user_id = n.user_id
  left join top_tag_concat ttc on ttc.user_id = n.user_id
  left join user_windows uw on uw.user_id = n.user_id
  left join activity_slope ats on ats.user_id = n.user_id
),
outlier_flags as (
  select
    f.*,
    case when f.reputation >= percentile_cont(0.99) within group (order by f.reputation) over ()
         then 1 else 0 end as is_rep_p99,
    case when coalesce(f.q_views_total,0) >= percentile_cont(0.99) within group (order by coalesce(f.q_views_total,0)) over ()
         then 1 else 0 end as is_views_p99,
    case when coalesce(f.net_votes_total,0) < percentile_cont(0.01) within group (order by coalesce(f.net_votes_total,0)) over ()
         then 1 else 0 end as is_netvotes_p01
  from final_users f
),
ranked as (
  select
    o.*,
    coalesce(o.q_count,0) + 2*coalesce(o.a_count,0) + 0.5*coalesce(o.comment_count,0) as activity_score,
    row_number() over (
      order by
        (coalesce(o.q_count,0) + 2*coalesce(o.a_count,0) + 0.5*coalesce(o.comment_count,0)) desc,
        o.reputation desc,
        o.user_id
    ) as activity_rank
  from outlier_flags o
)
select
  r.user_id,
  r.displayname,
  r.location_norm,
  r.reputation,
  r.rep_rank_overall,
  r.rep_rank_by_location,
  r.activity_rank,
  r.activity_score,
  r.q_count, r.a_count, r.comment_count,
  r.q_total, r.a_total,
  r.questions_with_accepted,
  r.accepted_answers,
  round(coalesce(r.avg_q_score,0)::numeric,2) as avg_q_score,
  round(coalesce(r.avg_a_score,0)::numeric,2) as avg_a_score,
  round(coalesce(r.avg_answers_per_q_nonzero,0)::numeric,2) as avg_answers_per_q_nonzero,
  r.p90_q_views,
  r.q_views_total,
  r.net_votes_total,
  r.flag_votes_total,
  r.bounty_total,
  r.dup_closes_total,
  r.dup_links_total,
  coalesce(r.top3_tags, '[none]') as top3_tags,
  r.last_activity,
  r.last_comment_date,
  r.last_badge_date,
  r.is_rep_p99,
  r.is_views_p99,
  r.is_netvotes_p01,
  case
    when r.is_rep_p99 = 1 and r.is_views_p99 = 1 then 'Elite'
    when r.is_rep_p99 = 1 then 'TopRep'
    when r.is_views_p99 = 1 then 'TopView'
    when r.is_netvotes_p01 = 1 then 'Controversial'
    else 'Regular'
  end as cohort_label
from ranked r
where
  (r.activity_score > 0 or r.reputation > 0)
  and coalesce(r.location_norm, '') not ilike '%bot%'
order by r.activity_rank, r.user_id
limit 500;