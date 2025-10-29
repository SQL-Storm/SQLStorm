-- {"query": "222.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3004}
with recent_users as (
  select
    u.id,
    u.displayname,
    u.reputation,
    u.creationdate,
    coalesce(nullif(trim(u.location), ''), 'Unknown') as location_norm,
    date_trunc('month', u.creationdate) as cohort_month,
    row_number() over (order by u.creationdate desc, u.id desc) as rn_global,
    row_number() over (partition by coalesce(nullif(trim(u.location), ''), 'Unknown') order by u.creationdate desc, u.id desc) as rn_by_location
  from users u
  where u.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '5 years'
),
badge_dims as (
  select
    b.userid,
    count(*) as total_badges,
    count(*) filter (where b.class = 1) as gold_badges,
    count(*) filter (where b.class = 2) as silver_badges,
    count(*) filter (where b.class = 3) as bronze_badges,
    min(b.date) as first_badge_date,
    max(b.date) as last_badge_date
  from badges b
  group by b.userid
),
user_activity as (
  select
    u.id as userid,
    count(*) filter (where p.posttypeid = 1) as q_count,
    count(*) filter (where p.posttypeid = 2) as a_count,
    sum(coalesce(p.score, 0)) as post_score_sum,
    max(p.lastactivitydate) as last_post_activity,
    sum(coalesce(p.viewcount, 0)) filter (where p.posttypeid = 1) as q_views_sum,
    avg(nullif(p.commentcount, 0)) as avg_commentcount_nonzero
  from users u
  left join posts p on p.owneruserid = u.id
  group by u.id
),
votes_agg as (
  select
    v.postid,
    sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
    sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
    sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites,
    sum(case when v.votetypeid = 8 then coalesce(v.bountyamount,0) else 0 end) as bounty_started,
    sum(case when v.votetypeid = 9 then coalesce(v.bountyamount,0) else 0 end) as bounty_awarded
  from votes v
  group by v.postid
),
question_metrics as (
  select
    p.id as question_id,
    p.owneruserid as q_ownerid,
    p.creationdate as q_created,
    p.score as q_score,
    p.viewcount as q_views,
    p.answercount as q_answers,
    p.favoritecount as q_favs,
    p.closeddate as q_closeddate,
    coalesce(v.upvotes,0) as upvotes,
    coalesce(v.downvotes,0) as downvotes,
    coalesce(v.favorites,0) as favorites_votes,
    coalesce(v.bounty_started,0) as bounty_started,
    coalesce(v.bounty_awarded,0) as bounty_awarded,
    case when p.tags is not null and length(p.tags) > 2
         then string_to_array(substring(p.tags from 2 for length(p.tags)-2), '><')
         else array[]::varchar[]
    end as tag_list
  from posts p
  left join votes_agg v on v.postid = p.id
  where p.posttypeid = 1
),
answers_per_question as (
  select
    a.parentid as question_id,
    count(*) as answers_total,
    sum(case when a.score > 0 then 1 else 0 end) as answers_positive,
    max(a.score) as max_answer_score,
    max(a.creationdate) as last_answer_date
  from posts a
  where a.posttypeid = 2
  group by a.parentid
),
close_reasons as (
  select
    ph.postid as question_id,
    max(ph.creationdate) filter (where ph.posthistorytypeid = 10) as last_closed_at,
    max(case
          when ph.posthistorytypeid = 10 then cast(ph.comment as integer)
          else null
        end) as last_close_reason_id
  from posthistory ph
  where ph.posthistorytypeid in (10,11)
  group by ph.postid
),
hotness as (
  select
    qm.question_id,
    qm.q_ownerid,
    qm.q_created,
    qm.q_score,
    qm.q_views,
    qm.q_answers,
    qm.q_favs as q_favs_count,
    qm.upvotes,
    qm.downvotes,
    qm.favorites_votes,
    qm.bounty_started,
    qm.bounty_awarded,
    apq.answers_total,
    apq.answers_positive,
    apq.max_answer_score,
    apq.last_answer_date,
    cr.last_closed_at,
    cr.last_close_reason_id,
    (coalesce(qm.q_views,0) * 0.001
     + coalesce(qm.q_score,0) * 2.0
     + coalesce(apq.answers_positive,0) * 3.0
     + least(coalesce(extract(epoch from (cast('2024-10-01 12:34:56' as timestamp) - qm.q_created)) / 86400.0, 9999), 365) * -0.05
     + (case when cr.last_closed_at is not null then -10 else 0 end)
     + least(coalesce(qm.downvotes,0), 50) * -0.5
     + greatest(coalesce(qm.upvotes,0) - coalesce(qm.downvotes,0), 0) * 0.25
     + case when coalesce(qm.bounty_started,0) > 0 then 5 else 0 end
    ) as hotness_score
  from question_metrics qm
  left join answers_per_question apq on apq.question_id = qm.question_id
  left join close_reasons cr on cr.question_id = qm.question_id
),
tag_explode as (
  select
    h.question_id,
    unnest(qm.tag_list) as tagname
  from question_metrics qm
  join hotness h on h.question_id = qm.question_id
),
tag_rank as (
  select
    te.tagname,
    count(*) as q_count,
    sum(case when h.hotness_score > 0 then 1 else 0 end) as hot_questions,
    avg(h.hotness_score) as avg_hotness,
    percentile_disc(0.9) within group (order by h.hotness_score) as p90_hotness
  from tag_explode te
  join hotness h on h.question_id = te.question_id
  group by te.tagname
),
user_rollup as (
  select
    ru.id as userid,
    ru.displayname,
    ru.location_norm,
    ru.cohort_month,
    ru.reputation,
    ua.q_count,
    ua.a_count,
    ua.post_score_sum,
    ua.last_post_activity,
    ua.q_views_sum,
    ua.avg_commentcount_nonzero,
    bd.total_badges,
    bd.gold_badges,
    bd.silver_badges,
    bd.bronze_badges,
    bd.first_badge_date,
    bd.last_badge_date,
    row_number() over (
      partition by ru.location_norm
      order by coalesce(ua.q_count,0) + coalesce(ua.a_count,0) desc,
               ru.reputation desc,
               ru.id
    ) as activity_rank_in_location
  from recent_users ru
  left join user_activity ua on ua.userid = ru.id
  left join badge_dims bd on bd.userid = ru.id
),
location_stats as (
  select
    ur.location_norm,
    count(*) as users_in_loc,
    avg(coalesce(ur.reputation,0)) as avg_rep,
    stddev_pop(cast(coalesce(ur.reputation,0) as numeric)) as std_rep,
    avg(coalesce(ur.q_count,0) + coalesce(ur.a_count,0)) as avg_posts,
    max(ur.last_post_activity) as last_activity_any
  from user_rollup ur
  group by ur.location_norm
),
location_quality as (
  select
    ls.location_norm,
    ls.users_in_loc,
    ls.avg_rep,
    ls.std_rep,
    ls.avg_posts,
    ls.last_activity_any,
    case
      when ls.users_in_loc >= 50 and ls.avg_rep > 1000 then 'Powerhouse'
      when ls.users_in_loc >= 20 and ls.avg_rep > 300 then 'Active'
      when ls.users_in_loc is null then 'Unknown'
      else 'Emerging'
    end as loc_class
  from location_stats ls
),
top_questions_per_user as (
  select
    h.q_ownerid as userid,
    h.question_id,
    h.hotness_score,
    row_number() over (partition by h.q_ownerid order by h.hotness_score desc, h.question_id desc) as rn_hot
  from hotness h
),
duplicate_graph as (
  select
    pl.postid as dup_post_id,
    pl.relatedpostid as canonical_id,
    count(*) over (partition by pl.relatedpostid) as dup_count_for_canonical
  from postlinks pl
  where pl.linktypeid = 3
),
question_flags as (
  select
    h.question_id,
    case when exists (
      select 1
      from duplicate_graph dg
      where dg.dup_post_id = h.question_id
    ) then 1 else 0 end as is_marked_duplicate,
    (select dg2.dup_count_for_canonical
     from duplicate_graph dg2
     where dg2.dup_post_id = h.question_id
     limit 1) as canonical_dup_count
  from hotness h
),
final_q as (
  select
    h.question_id,
    h.q_ownerid,
    h.hotness_score,
    qf.is_marked_duplicate,
    coalesce(qf.canonical_dup_count, 0) as canonical_dup_count,
    h.q_views,
    h.q_score,
    h.q_answers,
    h.last_closed_at
  from hotness h
  left join question_flags qf on qf.question_id = h.question_id
),
cohort_trends as (
  select
    ur.cohort_month,
    count(*) as users_in_cohort,
    avg(ur.reputation) as avg_rep_in_cohort,
    sum(coalesce(ur.q_count,0) + coalesce(ur.a_count,0)) as total_posts_in_cohort
  from user_rollup ur
  group by ur.cohort_month
),
ranked_tags as (
  select
    tr.tagname,
    tr.q_count,
    tr.hot_questions,
    tr.avg_hotness,
    tr.p90_hotness,
    dense_rank() over (order by tr.p90_hotness desc nulls last, tr.q_count desc) as dr_tag_hot
  from tag_rank tr
)
select
  ur.userid,
  ur.displayname,
  ur.location_norm,
  lq.loc_class,
  ur.cohort_month,
  ur.reputation,
  ur.q_count,
  ur.a_count,
  ur.post_score_sum,
  ur.total_badges,
  ur.gold_badges,
  ur.silver_badges,
  ur.bronze_badges,
  ls.users_in_loc,
  ls.avg_rep as avg_rep_in_location,
  ct.users_in_cohort,
  ct.avg_rep_in_cohort,
  tq.question_id as top_question_id,
  tq.hotness_score as top_question_hotness,
  fq.is_marked_duplicate,
  fq.canonical_dup_count,
  fq.q_views,
  fq.q_score,
  fq.q_answers,
  fq.last_closed_at,
  rt.tagname as top_tag_by_p90,
  rt.p90_hotness as top_tag_p90_hotness,
  coalesce(least(ur.reputation / nullif(cast(ls.avg_rep as numeric),0), 10), 0) as rep_vs_location_ratio_capped,
  case when ur.activity_rank_in_location <= greatest(ceil(ls.users_in_loc * 0.1), 1)
       then 'Top10pct'
       else 'Other'
  end as location_activity_bucket
from user_rollup ur
left join lateral (
  select tqu.question_id, tqu.hotness_score
  from top_questions_per_user tqu
  where tqu.userid = ur.userid and tqu.rn_hot = 1
) tq on true
left join final_q fq on fq.question_id = tq.question_id
left join location_stats ls on ls.location_norm = ur.location_norm
left join location_quality lq on lq.location_norm = ur.location_norm
left join cohort_trends ct on ct.cohort_month = ur.cohort_month
left join lateral (
  select rt.tagname, rt.p90_hotness
  from ranked_tags rt
  order by rt.dr_tag_hot
  limit 1
) rt on true
where
  (
    coalesce(ur.q_count,0) + coalesce(ur.a_count,0) >= 5
    or coalesce(ur.total_badges,0) >= 10
  )
  and not (
    ur.reputation is null
    or (ur.reputation <= 1 and coalesce(ur.q_count,0) = 0 and coalesce(ur.a_count,0) = 0)
  )
  and (
    (coalesce(fq.is_marked_duplicate, 0) <> 1)
    or coalesce(fq.canonical_dup_count,0) < 3
    or fq.last_closed_at is null
  )
order by
  coalesce(tq.hotness_score, -1) desc,
  ur.reputation desc,
  ur.userid
limit 500;