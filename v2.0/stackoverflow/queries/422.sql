with recent_users as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    cast(u.creationdate as date) as user_created,
    u.location,
    coalesce(nullif(trim(u.websiteurl), ''), 'n/a') as websiteurl_norm,
    count(case when b.class = 1 then 1 end) as gold_badges,
    count(case when b.class = 2 then 1 end) as silver_badges,
    count(case when b.class = 3 then 1 end) as bronze_badges,
    max(b.date) as last_badge_date
  from users u
  left join badges b
    on b.userid = u.id
    and b.date >= (cast('2024-10-01 12:34:56' as timestamp) - interval '3 years')
  where u.creationdate >= (cast('2024-10-01 12:34:56' as timestamp) - interval '10 years')
  group by u.id, u.displayname, u.reputation, u.creationdate, u.location, u.websiteurl
),
question_activity as (
  select
    p.owneruserid as user_id,
    p.id as post_id,
    p.creationdate,
    p.score,
    p.viewcount,
    p.answercount,
    p.favoritecount,
    p.closeddate,
    p.title,
    p.tags,
    count(c.id) as comment_count,
    sum(v.case_up) as upvotes,
    sum(v.case_down) as downvotes,
    sum(v.case_fav) as fav_votes
  from posts p
  left join lateral (
    select
      count(case when vt.votetypeid = 2 then 1 end) as case_up,
      count(case when vt.votetypeid = 3 then 1 end) as case_down,
      count(case when vt.votetypeid = 5 then 1 end) as case_fav
    from votes vt
    where vt.postid = p.id
  ) v on true
  left join comments c
    on c.postid = p.id
  where p.posttypeid = 1
    and p.creationdate >= (cast('2024-10-01 12:34:56' as timestamp) - interval '5 years')
  group by p.owneruserid, p.id, p.creationdate, p.score, p.viewcount, p.answercount, p.favoritecount, p.closeddate, p.title, p.tags
),
accepted_answerers as (
  select
    q.owneruserid as asker_id,
    a.owneruserid as answerer_id,
    q.id as question_id,
    a.id as answer_id,
    a.score as answer_score,
    q.acceptedanswerid
  from posts q
  join posts a
    on a.parentid = q.id
  where q.posttypeid = 1
    and a.posttypeid = 2
    and q.acceptedanswerid = a.id
),
tag_expansion as (
  select
    qa.post_id,
    unnest(string_to_array(substring(qa.tags, 2, greatest(length(qa.tags)-2,0)), '><')) as tagname
  from question_activity qa
  where qa.tags is not null
),
tag_stats as (
  select
    te.post_id,
    count(*) as tag_count,
    min(length(te.tagname)) as min_tag_len,
    max(length(te.tagname)) as max_tag_len,
    sum(length(te.tagname)) as sum_tag_len
  from tag_expansion te
  group by te.post_id
),
duplicate_graph as (
  select
    pl.postid as dup_post_id,
    pl.relatedpostid as canon_post_id,
    pl.creationdate as link_created
  from postlinks pl
  where pl.linktypeid = 3
),
dup_resolution as (
  select
    q.id as question_id,
    min(case when ph.posthistorytypeid in (11,20) then ph.creationdate end) as first_reopen_or_unprotect,
    min(case when ph.posthistorytypeid = 10 and ph.comment ~ '^[0-9]+$' then cast(ph.comment as int) end) as first_close_reason_raw,
    bool_or(ph.posthistorytypeid = 35) as migrated_away,
    bool_or(ph.posthistorytypeid = 36) as migrated_here
  from posts q
  left join posthistory ph
    on ph.postid = q.id
  where q.posttypeid = 1
  group by q.id
),
user_post_windows as (
  select
    qa.user_id,
    qa.post_id,
    qa.creationdate,
    qa.score,
    qa.viewcount,
    qa.answercount,
    qa.favoritecount,
    qa.upvotes,
    qa.downvotes,
    qa.fav_votes,
    count(*) over (partition by qa.user_id) as total_q_by_user,
    row_number() over (partition by qa.user_id order by qa.creationdate desc, qa.post_id desc) as rn_recent,
    avg(qa.score) over (partition by qa.user_id) as avg_score_user,
    qa.user_id as p90_user_marker,
    qa.viewcount as p90_view_for_calc
  from question_activity qa
),
user_p90_views as (
  select
    upw.user_id,
    percentile_cont(0.9) within group (order by upw.p90_view_for_calc) as p90_views_user
  from user_post_windows upw
  group by upw.user_id
),
user_post_windows_final as (
  select
    upw.user_id,
    upw.post_id,
    upw.creationdate,
    upw.score,
    upw.viewcount,
    upw.answercount,
    upw.favoritecount,
    upw.upvotes,
    upw.downvotes,
    upw.fav_votes,
    upw.total_q_by_user,
    upw.rn_recent,
    upw.avg_score_user,
    upv.p90_views_user
  from user_post_windows upw
  left join user_p90_views upv on upv.user_id = upw.user_id
),
heavy_users as (
  select
    ru.user_id,
    ru.displayname,
    ru.reputation,
    ru.user_created,
    ru.location,
    ru.websiteurl_norm,
    ru.gold_badges,
    ru.silver_badges,
    ru.bronze_badges,
    coalesce(ru.last_badge_date, ru.user_created) as last_activity_guess,
    sum(case when upw.score >= 0 then 1 else 0 end) as nonneg_q,
    sum(coalesce(upw.viewcount,0)) as total_views_q,
    avg(upw.score) as avg_q_score,
    count(upw.post_id) as q_count_5y
  from recent_users ru
  left join user_post_windows_final upw
    on upw.user_id = ru.user_id
  group by ru.user_id, ru.displayname, ru.reputation, ru.user_created, ru.location, ru.websiteurl_norm, ru.gold_badges, ru.silver_badges, ru.bronze_badges, coalesce(ru.last_badge_date, ru.user_created)
  having count(upw.post_id) >= 3
),
score_buckets as (
  select
    upw.post_id,
    case
      when upw.score >= 50 then 'S'
      when upw.score >= 10 then 'A'
      when upw.score >= 0 then 'B'
      when upw.score >= -5 then 'C'
      else 'D'
    end as score_bucket,
    upw.user_id
  from user_post_windows_final upw
),
per_post_agg as (
  select
    upw.user_id,
    upw.post_id,
    upw.creationdate,
    upw.score,
    coalesce(upw.viewcount,0) as viewcount,
    coalesce(upw.answercount,0) as answercount,
    coalesce(ts.tag_count, 0) as tag_count,
    coalesce(ts.min_tag_len, 0) as min_tag_len,
    coalesce(ts.max_tag_len, 0) as max_tag_len,
    coalesce(ts.sum_tag_len, 0) as sum_tag_len,
    coalesce(dr.first_close_reason_raw, 0) as first_close_reason_raw,
    coalesce((select count(*) from duplicate_graph dg where dg.dup_post_id = upw.post_id),0) as dup_out_edges,
    coalesce((select count(*) from duplicate_graph dg where dg.canon_post_id = upw.post_id),0) as dup_in_edges
  from user_post_windows_final upw
  left join tag_stats ts on ts.post_id = upw.post_id
  left join dup_resolution dr on dr.question_id = upw.post_id
),
cross_user_influence as (
  select
    aa.answerer_id as other_user_id,
    aa.asker_id as base_user_id,
    count(*) as accepted_pairs,
    avg(aa.answer_score) as avg_answer_score_to_base
  from accepted_answerers aa
  group by aa.answerer_id, aa.asker_id
),
normalized as (
  select
    ppa.user_id,
    ppa.post_id,
    ppa.creationdate,
    ppa.score,
    ppa.viewcount,
    ppa.answercount,
    ppa.tag_count,
    ppa.min_tag_len,
    ppa.max_tag_len,
    ppa.sum_tag_len,
    ppa.first_close_reason_raw,
    ppa.dup_out_edges,
    ppa.dup_in_edges,
    sb.score_bucket,
    case when ppa.viewcount > 0 then cast(ppa.score as numeric) / ppa.viewcount else null end as score_per_view,
    case when ppa.answercount > 0 then cast(ppa.score as numeric) / ppa.answercount else null end as score_per_answer
  from per_post_agg ppa
  left join score_buckets sb on sb.post_id = ppa.post_id
),
ranked_posts as (
  select
    n.*,
    row_number() over (
      partition by n.user_id
      order by coalesce(n.score_per_view, -1) desc, n.viewcount desc, n.post_id desc
    ) as rn_best_spv
  from normalized n
),
combined as (
  select
    hu.user_id,
    hu.displayname,
    hu.reputation,
    hu.location,
    hu.websiteurl_norm,
    hu.gold_badges,
    hu.silver_badges,
    hu.bronze_badges,
    hu.q_count_5y,
    hu.avg_q_score,
    hu.total_views_q,
    rp.post_id,
    rp.creationdate,
    rp.score,
    rp.viewcount,
    rp.answercount,
    rp.tag_count,
    rp.min_tag_len,
    rp.max_tag_len,
    rp.sum_tag_len,
    rp.score_bucket,
    rp.score_per_view,
    rp.score_per_answer,
    rp.first_close_reason_raw,
    rp.dup_out_edges,
    rp.dup_in_edges,
    cui.accepted_pairs,
    cui.avg_answer_score_to_base
  from heavy_users hu
  join ranked_posts rp
    on rp.user_id = hu.user_id
   and rp.rn_best_spv <= 5
  left join cross_user_influence cui
    on cui.base_user_id = hu.user_id
)
select
  c.user_id,
  c.displayname,
  c.reputation,
  coalesce(nullif(trim(c.location), ''), 'Unknown') as location_norm,
  c.websiteurl_norm,
  c.gold_badges,
  c.silver_badges,
  c.bronze_badges,
  c.q_count_5y,
  round(coalesce(c.avg_q_score,0), 2) as avg_q_score,
  c.total_views_q,
  c.post_id,
  cast(c.creationdate as date) as post_date,
  c.score,
  c.viewcount,
  c.answercount,
  c.tag_count,
  c.min_tag_len,
  c.max_tag_len,
  c.sum_tag_len,
  c.score_bucket,
  round(c.score_per_view, 6) as score_per_view,
  round(c.score_per_answer, 6) as score_per_answer,
  c.first_close_reason_raw,
  c.dup_out_edges,
  c.dup_in_edges,
  coalesce(c.accepted_pairs, 0) as accepted_pairs_from_others,
  round(coalesce(c.avg_answer_score_to_base,0), 2) as avg_answer_score_from_others,
  case
    when c.score_bucket in ('S','A') and c.dup_out_edges = 0 and (c.first_close_reason_raw is null or c.first_close_reason_raw = 0) then 'elite'
    when c.score_bucket in ('B','C') then 'normal'
    else 'needs_help'
  end as user_post_tier
from combined c
where (
    c.gold_badges > 0
    or c.reputation >= 1000
    or (c.q_count_5y >= 5 and c.total_views_q >= 1000)
  )
  and (
    c.score_per_view is not null
    or c.score >= 5
    or (c.dup_in_edges + c.dup_out_edges) > 0
  )
order by
  user_post_tier,
  c.gold_badges desc,
  c.reputation desc,
  c.score_per_view desc,
  c.viewcount desc,
  c.post_id desc;