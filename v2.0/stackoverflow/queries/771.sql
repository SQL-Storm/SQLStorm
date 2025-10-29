-- {"query": "771.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3015}
with recent_users as (
  select
    u.id,
    u.displayname,
    u.reputation,
    u.creationdate,
    u.location,
    coalesce(nullif(trim(u.websiteurl), ''), 'N/A') as websiteurl,
    date_trunc('month', u.creationdate) as cohort_month,
    ntile(4) over (order by u.reputation desc nulls last) as rep_quartile
  from users u
  where u.creationdate >= (
    select date_trunc('year', max(p.creationdate)) - interval '1 year' from posts p
  )
),
user_activity as (
  select
    u.id as user_id,
    count(*) filter (where p.posttypeid = 1) as q_count,
    count(*) filter (where p.posttypeid = 2) as a_count,
    sum(p.score) as total_post_score,
    sum(coalesce(p.viewcount, 0)) as total_views,
    max(p.creationdate) as last_post_date
  from recent_users u
  left join posts p
    on p.owneruserid = u.id
   and p.creationdate >= u.creationdate
  group by u.id
),
comment_stats as (
  select
    u.id as user_id,
    count(c.id) as comment_count,
    sum(c.score) as comment_score_sum,
    avg(nullif(c.score, 0)) as avg_nonzero_comment_score,
    max(c.creationdate) as last_comment_date
  from recent_users u
  left join comments c
    on c.userid = u.id
   and c.creationdate >= u.creationdate
  group by u.id
),
badge_stats as (
  select
    u.id as user_id,
    count(b.id) as badge_count,
    count(*) filter (where b.class = 1) as gold_count,
    count(*) filter (where b.class = 2) as silver_count,
    count(*) filter (where b.class = 3) as bronze_count,
    min(b.date) as first_badge_date,
    max(b.date) as last_badge_date
  from recent_users u
  left join badges b
    on b.userid = u.id
   and b.date >= u.creationdate
  group by u.id
),
vote_stats as (
  select
    u.id as user_id,
    count(*) filter (where v.votetypeid = 2) as upvotes_cast,
    count(*) filter (where v.votetypeid = 3) as downvotes_cast,
    count(*) filter (where v.votetypeid = 5) as favorites_cast,
    max(v.creationdate) as last_vote_date
  from recent_users u
  left join votes v
    on v.userid = u.id
   and v.creationdate >= u.creationdate
  group by u.id
),
post_quality as (
  select
    u.id as user_id,
    avg(p.score) filter (where p.posttypeid in (1,2)) as avg_post_score,
    percentile_cont(0.5) within group (order by p.score) filter (where p.posttypeid in (1,2)) as median_post_score,
    stddev_pop(p.score) filter (where p.posttypeid in (1,2)) as score_stddev,
    sum(case when p.posttypeid = 1 and p.acceptedanswerid is not null then 1 else 0 end) as accepted_q_count,
    sum(case when p.posttypeid = 2 and exists (
      select 1
      from posts q
      where q.id = p.parentid
        and q.acceptedanswerid = p.id
    ) then 1 else 0 end) as accepted_a_count
  from recent_users u
  left join posts p
    on p.owneruserid = u.id
  group by u.id
),
question_tag_breakdown as (
  select
    p.owneruserid as user_id,
    unnest(string_to_array(substring(p.tags, 2, greatest(length(p.tags)-2,0)), '><')) as tagname,
    count(*) as tag_q_count
  from posts p
  where p.posttypeid = 1
    and p.owneruserid is not null
    and p.tags is not null
  group by p.owneruserid, tagname
),
top_tags as (
  select
    qt.user_id,
    string_agg(tagname || ':' || cast(tag_q_count as text), ', ' order by tag_q_count desc, tagname) as tag_summary,
    array_to_string(array_agg(tagname order by tag_q_count desc, tagname), ', ') as top3_tags
  from question_tag_breakdown qt
  group by qt.user_id
),
postlink_dupes as (
  select
    u.id as user_id,
    count(pl.id) filter (where pl.linktypeid = 3) as duplicate_links,
    count(pl.id) filter (where pl.linktypeid = 1) as linked_links
  from recent_users u
  left join posts p on p.owneruserid = u.id
  left join postlinks pl on pl.postid = p.id
  group by u.id
),
close_events as (
  select
    ph.postid,
    min(ph.creationdate) as first_close_date,
    count(*) as close_event_count,
    count(*) filter (where ph.comment in ('101','102','103','104','105','1','2','3','4','7','10','20')) as with_reason_count
  from posthistory ph
  where ph.posthistorytypeid in (10,11,35)
  group by ph.postid
),
question_lifecycle as (
  select
    q.id as post_id,
    q.owneruserid as user_id,
    q.creationdate as q_created,
    ce.first_close_date,
    extract(epoch from (ce.first_close_date - q.creationdate))/3600.0 as hours_to_first_close,
    q.viewcount,
    q.score
  from posts q
  left join close_events ce on ce.postid = q.id
  where q.posttypeid = 1
),
answered_by_user as (
  select
    a.owneruserid as user_id,
    count(distinct a.parentid) as distinct_questions_answered,
    sum(case when a.score > 0 then 1 else 0 end) as positive_answers,
    avg(a.score) as avg_answer_score,
    max(a.creationdate) as last_answer_date
  from posts a
  where a.posttypeid = 2
  group by a.owneruserid
),
question_resolution as (
  select
    q.owneruserid as user_id,
    count(*) as questions_posted,
    sum(case when q.acceptedanswerid is not null then 1 else 0 end) as questions_with_accepted,
    avg(extract(epoch from (a.creationdate - q.creationdate))/3600.0) filter (where a.id = q.acceptedanswerid) as avg_hours_to_accept
  from posts q
  left join posts a on a.id = q.acceptedanswerid
  where q.posttypeid = 1
  group by q.owneruserid
),
rep_velocity as (
  select
    u.id as user_id,
    extract(epoch from (coalesce(nullif(u.lastaccessdate, timestamp 'epoch'), cast('2024-10-01 12:34:56' as timestamp)) - u.creationdate))/86400.0 as days_since_join,
    case when extract(epoch from (coalesce(nullif(u.lastaccessdate, timestamp 'epoch'), cast('2024-10-01 12:34:56' as timestamp)) - u.creationdate)) > 0
         then u.reputation / (extract(epoch from (coalesce(nullif(u.lastaccessdate, timestamp 'epoch'), cast('2024-10-01 12:34:56' as timestamp)) - u.creationdate))/86400.0)
         else null end as rep_per_day
  from users u
),
user_ranked as (
  select
    ru.id,
    ru.displayname,
    ru.reputation,
    ru.creationdate,
    ru.location,
    ru.websiteurl,
    ru.cohort_month,
    ru.rep_quartile,
    ua.q_count,
    ua.a_count,
    ua.total_post_score,
    ua.total_views,
    ua.last_post_date,
    cs.comment_count,
    cs.comment_score_sum,
    cs.avg_nonzero_comment_score,
    cs.last_comment_date,
    bs.badge_count,
    bs.gold_count,
    bs.silver_count,
    bs.bronze_count,
    bs.first_badge_date,
    bs.last_badge_date,
    vs.upvotes_cast,
    vs.downvotes_cast,
    vs.favorites_cast,
    vs.last_vote_date,
    pq.avg_post_score,
    pq.median_post_score,
    pq.score_stddev,
    pq.accepted_q_count,
    pq.accepted_a_count,
    coalesce(pt.duplicate_links, 0) as duplicate_links,
    coalesce(pt.linked_links, 0) as linked_links,
    at.distinct_questions_answered,
    at.positive_answers,
    at.avg_answer_score,
    at.last_answer_date,
    qr.questions_posted,
    qr.questions_with_accepted,
    qr.avg_hours_to_accept,
    tt.tag_summary,
    tt.top3_tags,
    rv.days_since_join,
    rv.rep_per_day,
    dense_rank() over (
      order by
        coalesce(ua.total_post_score,0) + coalesce(cs.comment_score_sum,0) + coalesce(bs.badge_count,0) * 5
        + coalesce(pq.accepted_a_count,0) * 10 + coalesce(qr.questions_with_accepted,0) * 3
        + coalesce(vs.upvotes_cast,0) * 0.1 - coalesce(vs.downvotes_cast,0) * 0.2
        + coalesce(rv.rep_per_day,0) * 0.5
      desc
    ) as perf_rank
  from recent_users ru
  left join user_activity ua on ua.user_id = ru.id
  left join comment_stats cs on cs.user_id = ru.id
  left join badge_stats bs on bs.user_id = ru.id
  left join vote_stats vs on vs.user_id = ru.id
  left join post_quality pq on pq.user_id = ru.id
  left join postlink_dupes pt on pt.user_id = ru.id
  left join answered_by_user at on at.user_id = ru.id
  left join question_resolution qr on qr.user_id = ru.id
  left join top_tags tt on tt.user_id = ru.id
  left join rep_velocity rv on rv.user_id = ru.id
),
cohort_agg as (
  select
    cohort_month,
    count(*) as users_in_cohort,
    avg(coalesce(rep_per_day, 0)) as avg_rep_per_day,
    percentile_cont(0.9) within group (order by coalesce(total_post_score,0)) as p90_total_post_score,
    avg(cast(coalesce(questions_with_accepted,0) as double precision) / nullif(questions_posted,0)) as avg_q_accept_rate,
    sum(case when perf_rank <= 10 then 1 else 0 end) as top10_count
  from user_ranked
  group by cohort_month
),
cross_user_extremes as (
  select
    (select id from user_ranked order by coalesce(rep_per_day, -1) desc nulls last, id limit 1) as fastest_rep_user,
    (select id from user_ranked order by coalesce(total_views, -1) desc nulls last, id limit 1) as most_views_user,
    (select id from user_ranked order by coalesce(median_post_score, -1) desc nulls last, id limit 1) as highest_median_score_user
)
select
  ur.id as user_id,
  ur.displayname,
  ur.location,
  ur.reputation,
  ur.rep_quartile,
  ur.cohort_month,
  ur.q_count,
  ur.a_count,
  ur.total_post_score,
  ur.median_post_score,
  ur.score_stddev,
  ur.accepted_q_count,
  ur.accepted_a_count,
  ur.questions_posted,
  ur.questions_with_accepted,
  round(cast(ur.avg_hours_to_accept as numeric), 2) as avg_hours_to_accept,
  ur.comment_count,
  ur.comment_score_sum,
  round(cast(ur.avg_nonzero_comment_score as numeric), 3) as avg_nonzero_comment_score,
  ur.badge_count,
  ur.gold_count,
  ur.silver_count,
  ur.bronze_count,
  ur.upvotes_cast,
  ur.downvotes_cast,
  ur.duplicate_links,
  ur.linked_links,
  ur.distinct_questions_answered,
  round(cast(ur.avg_answer_score as numeric), 2) as avg_answer_score,
  ur.tag_summary,
  coalesce(ur.top3_tags, 'none') as top3_tags,
  round(cast(coalesce(ur.rep_per_day, 0) as numeric), 3) as rep_per_day,
  ur.perf_rank,
  ca.users_in_cohort,
  round(cast(ca.avg_rep_per_day as numeric), 3) as cohort_avg_rep_per_day,
  ca.p90_total_post_score,
  round(cast(coalesce(ca.avg_q_accept_rate, 0) as numeric), 3) as cohort_avg_q_accept_rate,
  case when ur.id = cue.fastest_rep_user then 'fastest_rep' end as fastest_rep_flag,
  case when ur.id = cue.most_views_user then 'most_views' end as most_views_flag,
  case when ur.id = cue.highest_median_score_user then 'highest_median_score' end as highest_median_score_flag
from user_ranked ur
left join cohort_agg ca on ca.cohort_month = ur.cohort_month
cross join cross_user_extremes cue
where (
    ur.perf_rank <= 100
    or ur.rep_quartile = 1
    or (coalesce(ur.total_post_score,0) > ca.p90_total_post_score and ca.users_in_cohort >= 5)
)
and (
    ur.websiteurl like '%github%'
    or (ur.location ilike '%USA%' or ur.location ilike '%UK%' or ur.location ilike '%India%' or ur.location ilike '%Canada%' or ur.location ilike '%Germany%')
    or (ur.badge_count >= 10 and (coalesce(ur.q_count,0) + coalesce(ur.a_count,0)) >= 5)
)
order by ur.perf_rank, ur.reputation desc, ur.id
limit 200;