-- {"query": "214.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3030} 
with recent_users as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    u.creationdate,
    coalesce(nullif(trim(u.location), ''), 'Unknown') as location_norm,
    date_trunc('month', u.creationdate) as cohort_month,
    row_number() over (partition by coalesce(nullif(trim(u.location), ''), 'Unknown') order by u.reputation desc, u.id) as rep_rank_in_location
  from users u
  where u.creationdate >= now() - interval '5 years'
),
user_posts as (
  select
    p.owneruserid as user_id,
    p.id as post_id,
    p.posttypeid,
    p.creationdate,
    p.score,
    p.viewcount,
    p.answercount,
    p.title,
    p.tags,
    (
      select count(1)
      from comments c
      where c.postid = p.id
        and c.creationdate <= p.creationdate + interval '7 days'
    ) as early_comment_count,
    (
      select count(1)
      from votes v
      where v.postid = p.id
        and v.votetypeid in (2,3)
        and v.creationdate <= p.creationdate + interval '7 days'
    ) as early_vote_count
  from posts p
  where p.owneruserid is not null
    and p.creationdate >= now() - interval '5 years'
),
post_link_stats as (
  select
    pl.postid,
    sum(case when pl.linktypeid = 1 then 1 else 0 end) as linked_count,
    sum(case when pl.linktypeid = 3 then 1 else 0 end) as dup_count,
    count(*) as link_total
  from postlinks pl
  group by pl.postid
),
accepted_answer_latency as (
  select
    q.id as question_id,
    q.owneruserid as asker_id,
    q.creationdate as question_created,
    a.id as accepted_answer_id,
    a.owneruserid as answerer_id,
    a.creationdate as answer_created,
    extract(epoch from (a.creationdate - q.creationdate)) / 3600.0 as hours_to_accept
  from posts q
  join posts a on a.id = q.acceptedanswerid
  where q.posttypeid = 1
),
user_activity as (
  select
    up.user_id,
    count(*) filter (where up.posttypeid = 1) as questions,
    count(*) filter (where up.posttypeid = 2) as answers,
    sum(greatest(up.score, 0)) as nonneg_score_sum,
    avg(nullif(up.viewcount, 0)) as avg_views_nonzero,
    sum(up.early_comment_count) as early_comments_7d,
    sum(up.early_vote_count) as early_votes_7d,
    max(up.creationdate) as last_post_date
  from user_posts up
  group by up.user_id
),
user_badges as (
  select
    b.userid as user_id,
    count(*) as badge_count,
    count(*) filter (where b.class = 1) as gold_count,
    count(*) filter (where b.class = 2) as silver_count,
    count(*) filter (where b.class = 3) as bronze_count,
    min(b.date) as first_badge_date,
    max(b.date) as last_badge_date
  from badges b
  where b.date >= now() - interval '5 years'
  group by b.userid
),
question_quality as (
  select
    q.id as question_id,
    q.owneruserid as user_id,
    q.score,
    q.viewcount,
    q.answercount,
    length(coalesce(q.body, '')) as body_len,
    case when q.closeddate is not null then 1 else 0 end as is_closed,
    pls.dup_count,
    pls.linked_count,
    regexp_replace(coalesce(q.title, ''), '\s+', ' ', 'g') as title_norm,
    (
      select count(1)
      from comments c
      where c.postid = q.id
        and c.score > 0
    ) as pos_comment_count
  from posts q
  left join post_link_stats pls on pls.postid = q.id
  where q.posttypeid = 1
    and q.creationdate >= now() - interval '5 years'
),
tag_exploded as (
  select
    q.user_id,
    q.question_id,
    unnest(string_to_array(substring(q.tags, 2, length(q.tags)-2), '><')) as tag
  from posts q
  where q.posttypeid = 1
    and q.tags is not null
    and q.creationdate >= now() - interval '5 years'
),
top_tags_per_user as (
  select
    te.user_id,
    te.tag,
    count(*) as tag_uses,
    row_number() over (partition by te.user_id order by count(*) desc, te.tag) as rn
  from tag_exploded te
  group by te.user_id, te.tag
),
close_reasons as (
  select
    ph.postid,
    max(case when ph.posthistorytypeid = 10 then try_cast(ph.comment as int) end) as last_close_reason_id,
    max(ph.creationdate) filter (where ph.posthistorytypeid = 10) as last_closed_at
  from posthistory ph
  where ph.posthistorytypeid in (10,11)
  group by ph.postid
),
recent_commenters as (
  select
    c.postid,
    count(distinct c.userid) as distinct_commenters_30d
  from comments c
  join posts p on p.id = c.postid
  where c.creationdate between p.creationdate and p.creationdate + interval '30 days'
  group by c.postid
),
vote_rollups as (
  select
    v.postid,
    sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
    sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
    sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites
  from votes v
  group by v.postid
),
engagement as (
  select
    qq.question_id,
    coalesce(rc.distinct_commenters_30d, 0) as commenters_30d,
    coalesce(vr.upvotes, 0) as upvotes,
    coalesce(vr.downvotes, 0) as downvotes,
    coalesce(vr.favorites, 0) as favorites
  from question_quality qq
  left join recent_commenters rc on rc.postid = qq.question_id
  left join vote_rollups vr on vr.postid = qq.question_id
),
user_quality as (
  select
    qq.user_id,
    percentile_cont(0.5) within group (order by qq.score) as median_q_score,
    avg(qq.viewcount) as avg_q_views,
    avg(case when qq.is_closed = 1 then 1.0 else 0.0 end) as close_rate,
    avg(least(coalesce(qq.dup_count,0), 1)) as dup_rate,
    avg(qq.body_len) as avg_body_len,
    avg(e.upvotes - e.downvotes) as avg_vote_delta,
    avg(e.commenters_30d) as avg_commenters_30d
  from question_quality qq
  left join engagement e on e.question_id = qq.question_id
  group by qq.user_id
),
cohort_stats as (
  select
    ru.cohort_month,
    count(*) as users_in_cohort,
    avg(ua.questions + ua.answers) as avg_posts_per_user,
    percentile_disc(0.9) within group (order by ua.nonneg_score_sum) as p90_nonneg_score_sum
  from recent_users ru
  left join user_activity ua on ua.user_id = ru.user_id
  group by ru.cohort_month
),
ranked_questions as (
  select
    qq.question_id,
    qq.user_id,
    qq.score,
    qq.viewcount,
    qq.answercount,
    qq.is_closed,
    e.upvotes,
    e.downvotes,
    e.favorites,
    row_number() over (
      partition by qq.user_id
      order by (coalesce(e.upvotes,0) - coalesce(e.downvotes,0)) desc, qq.viewcount desc, qq.score desc, qq.question_id
    ) as rn_by_user
  from question_quality qq
  left join engagement e on e.question_id = qq.question_id
),
dup_clusters as (
  select
    q.user_id,
    count(*) filter (where qq.is_closed = 1 and coalesce(cr.last_close_reason_id,0) in (1,101)) as dup_closed_count
  from question_quality qq
  left join close_reasons cr on cr.postid = qq.question_id
  join posts q on q.id = qq.question_id
  group by q.user_id
),
final_users as (
  select
    ru.user_id,
    ru.displayname,
    ru.location_norm,
    ru.reputation,
    ru.cohort_month,
    ru.rep_rank_in_location,
    ua.questions,
    ua.answers,
    ua.nonneg_score_sum,
    ua.avg_views_nonzero,
    ua.early_comments_7d,
    ua.early_votes_7d,
    ua.last_post_date,
    uq.median_q_score,
    uq.avg_q_views,
    uq.close_rate,
    uq.dup_rate,
    uq.avg_body_len,
    uq.avg_vote_delta,
    uq.avg_commenters_30d,
    db.dup_closed_count,
    ub.badge_count,
    ub.gold_count,
    ub.silver_count,
    ub.bronze_count,
    ub.first_badge_date,
    ub.last_badge_date,
    tt.tag as top_tag
  from recent_users ru
  left join user_activity ua on ua.user_id = ru.user_id
  left join user_quality uq on uq.user_id = ru.user_id
  left join dup_clusters db on db.user_id = ru.user_id
  left join user_badges ub on ub.user_id = ru.user_id
  left join top_tags_per_user tt on tt.user_id = ru.user_id and tt.rn = 1
),
flag_anomalies as (
  select
    fu.user_id,
    case
      when coalesce(fu.answers,0) = 0 and coalesce(fu.questions,0) = 0 then 'inactive'
      when fu.close_rate > 0.5 and fu.reputation < 500 then 'high-close-low-rep'
      when fu.nonneg_score_sum < 0 and coalesce(fu.answers,0) + coalesce(fu.questions,0) > 10 then 'negative-heavy-poster'
      when fu.avg_vote_delta < -1 then 'downvoted'
      when fu.dup_closed_count >= 3 then 'frequent-duplicate'
      else null
    end as anomaly_flag
  from final_users fu
),
location_peers as (
  select
    fu.location_norm,
    percentile_cont(0.75) within group (order by fu.reputation) as p75_rep_loc,
    avg(coalesce(fu.answers,0) + coalesce(fu.questions,0)) as avg_posts_loc
  from final_users fu
  group by fu.location_norm
)
select
  fu.user_id,
  fu.displayname,
  fu.location_norm,
  fu.reputation,
  fu.cohort_month,
  fu.rep_rank_in_location,
  coalesce(fu.questions,0) as questions,
  coalesce(fu.answers,0) as answers,
  coalesce(fu.nonneg_score_sum,0) as nonneg_score_sum,
  round(coalesce(fu.avg_views_nonzero,0)::numeric,2) as avg_views_nonzero,
  round(coalesce(fu.median_q_score,0)::numeric,2) as median_q_score,
  round(coalesce(fu.avg_q_views,0)::numeric,2) as avg_q_views,
  round(coalesce(fu.close_rate,0)::numeric,3) as close_rate,
  round(coalesce(fu.dup_rate,0)::numeric,3) as dup_rate,
  round(coalesce(fu.avg_vote_delta,0)::numeric,2) as avg_vote_delta,
  round(coalesce(fu.avg_commenters_30d,0)::numeric,2) as avg_commenters_30d,
  coalesce(fu.dup_closed_count,0) as dup_closed_count,
  coalesce(fu.badge_count,0) as badge_count,
  coalesce(fu.gold_count,0) as gold_badges,
  coalesce(fu.silver_count,0) as silver_badges,
  coalesce(fu.bronze_count,0) as bronze_badges,
  fu.first_badge_date,
  fu.last_badge_date,
  coalesce(fu.top_tag, '(none)') as top_tag,
  rp.question_id as top_question_id,
  rp.score as top_question_score,
  rp.viewcount as top_question_views,
  rp.answercount as top_question_answers,
  case when fu.reputation >= lp.p75_rep_loc then 'top-quartile-in-location' else 'below-p75' end as location_rep_bucket,
  ap.anomaly_flag
from final_users fu
left join ranked_questions rp
  on rp.user_id = fu.user_id and rp.rn_by_user = 1
left join location_peers lp
  on lp.location_norm = fu.location_norm
left join flag_anomalies ap
  on ap.user_id = fu.user_id
where
  (
    fu.rep_rank_in_location <= 50
    or coalesce(fu.badge_count,0) >= 10
    or coalesce(fu.answers,0) + coalesce(fu.questions,0) >= 50
    or ap.anomaly_flag is not null
  )
order by
  fu.location_norm,
  fu.rep_rank_in_location nulls last,
  fu.reputation desc,
  fu.user_id
limit 5000;