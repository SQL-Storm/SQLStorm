with
user_activity as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    u.creationdate as user_created,
    coalesce(sum(case when p.posttypeid = 1 then 1 else 0 end), 0) as questions,
    coalesce(sum(case when p.posttypeid = 2 then 1 else 0 end), 0) as answers,
    coalesce(sum(p.viewcount), 0) as total_views,
    coalesce(sum(p.score), 0) as total_post_score,
    coalesce(sum(p.commentcount), 0) as total_comment_count,
    count(distinct v.id) filter (where v.votetypeid = 2) as upvotes_given,
    count(distinct v.id) filter (where v.votetypeid = 3) as downvotes_given,
    count(distinct case when v.votetypeid in (8,9) then v.id end) as bounties_interactions,
    max(p.lastactivitydate) as last_post_activity
  from users u
  left join posts p on p.owneruserid = u.id
  left join votes v on v.userid = u.id
  group by u.id, u.displayname, u.reputation, u.creationdate
),
user_activity_ranked as (
  select
    ua.user_id,
    ua.displayname,
    ua.reputation,
    ua.user_created,
    ua.questions,
    ua.answers,
    ua.total_views,
    ua.total_post_score,
    ua.total_comment_count,
    ua.upvotes_given,
    ua.downvotes_given,
    ua.bounties_interactions,
    ua.last_post_activity,
    row_number() over (order by ua.total_post_score desc nulls last, ua.total_views desc nulls last) as rn_score,
    row_number() over (order by ua.questions desc nulls last) as rn_questions,
    row_number() over (order by ua.answers desc nulls last) as rn_answers,
    dense_rank() over (order by ua.upvotes_given desc nulls last) as dr_up_given,
    rank() over (order by ua.downvotes_given desc nulls last) as r_down_given
  from user_activity ua
),
badge_agg as (
  select
    b.userid,
    count(*) as badges_total,
    sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
    sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
    sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
    sum(case when coalesce(b.tagbased, false) = true then 1 else 0 end) as tag_badges,
    min(b.date) as first_badge_date,
    max(b.date) as last_badge_date
  from badges b
  group by b.userid
),
question_tags as (
  select
    p.id as post_id,
    lower(trim(t)) as tag
  from posts p
  cross join lateral unnest(
    case
      when p.posttypeid = 1 and p.tags is not null and length(p.tags) >= 2
        then string_to_array(substring(p.tags from 2 for length(p.tags)-2), '><')
      else array[]::text[]  -- keep this array literal as standard SQL arrays are dialect-specific; many engines accept this. If not, replace with explicit empty table source.
    end
  ) as t
),
tag_popularity as (
  select
    qt.tag,
    count(*) as tag_usage_count,
    ntile(10) over (order by count(*) desc) as popularity_decile
  from question_tags qt
  group by qt.tag
),
post_metrics as (
  select
    p.id,
    p.posttypeid,
    p.owneruserid,
    p.creationdate,
    p.score,
    p.viewcount,
    p.answercount,
    p.favoritecount,
    p.commentcount,
    p.title,
    p.tags,
    (coalesce(p.score,0) * 3)
      + (coalesce(p.viewcount,0) / nullif(100,0))
      + (coalesce(p.answercount,0) * 5)
      + (coalesce(p.commentcount,0) * 2)
      + (coalesce(p.favoritecount,0) * 4) as engagement_score,
    length(coalesce(p.title,'')) as title_len,
    nullif(length(regexp_replace(coalesce(p.title,''), '[^aeiouAEIOU]', '', 'g')),0) * 1.0
      / nullif(length(coalesce(p.title,'')),0) as title_vowel_ratio,
    exists (
      select 1
      from postlinks pl
      where pl.postid = p.id
        and pl.linktypeid = 3
    ) as has_duplicate_link,
    (
      select avg(extract(epoch from (pa.creationdate - p.creationdate)))
      from posts pa
      where pa.id = p.acceptedanswerid
    ) as sec_to_accept
  from posts p
  where p.posttypeid in (1,2)
),
post_metrics_windowed as (
  select
    pm.id,
    pm.posttypeid,
    pm.owneruserid,
    pm.creationdate,
    pm.score,
    pm.viewcount,
    pm.answercount,
    pm.favoritecount,
    pm.commentcount,
    pm.title,
    pm.tags,
    pm.engagement_score,
    pm.title_len,
    pm.title_vowel_ratio,
    pm.has_duplicate_link,
    pm.sec_to_accept,
    case when pm.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '365 days' then 1 else 0 end as is_recent,
    sum(case when pm.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '365 days' then 1 else 0 end)
      over (partition by pm.owneruserid) as recent_posts_count_user,
    sum(pm.engagement_score) filter (where pm.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '365 days')
      over (partition by pm.owneruserid) as recent_engagement_user,
    avg(pm.engagement_score) over (partition by pm.owneruserid) as avg_engagement_user,
    -- Replace ordered-set aggregate with windowed percentile approximation using percentile_cont as a window function is not standard.
    -- Use percentile_disc with FILTER over aggregated subquery per user instead.
    null as p90_engagement_user,
    row_number() over (partition by pm.owneruserid order by pm.engagement_score desc nulls last) as rn_engagement_user
  from post_metrics pm
),
post_metrics_user_percentiles as (
  select
    owneruserid as user_id,
    percentile_cont(0.9) within group (order by engagement_score) as p90_engagement_user
  from post_metrics
  group by owneruserid
),
post_closure as (
  select
    ph.postid,
    max(case when ph.posthistorytypeid = 10 then 1 else 0 end) as ever_closed,
    max(case when ph.posthistorytypeid = 11 then 1 else 0 end) as ever_reopened,
    max(case when ph.posthistorytypeid in (14) then 1 else 0 end) as ever_locked,
    min(case when ph.posthistorytypeid = 10 then ph.creationdate end) as first_closed_at,
    max(case when ph.posthistorytypeid = 11 then ph.creationdate end) as last_reopened_at,
    nullif(regexp_replace(coalesce(ph.comment,''), '[^0-9]', '', 'g'), '') as parsed_close_reason_text
  from posthistory ph
  where ph.posthistorytypeid in (10,11,14)
  group by ph.postid, nullif(regexp_replace(coalesce(ph.comment,''), '[^0-9]', '', 'g'), '')
),
closure_reason_lu as (
  select
    pc.postid,
    max(crt.name) as close_reason_name
  from post_closure pc
  left join closereasontypes crt
    on crt.id = case when pc.parsed_close_reason_text ~ '^[0-9]+$' then cast(pc.parsed_close_reason_text as integer) else null end
  group by pc.postid
),
duplicate_clusters as (
  select
    pl.postid,
    count(*) filter (where pl.linktypeid = 3) as dup_links_out,
    count(*) filter (where pl.linktypeid = 1) as linked_out
  from postlinks pl
  group by pl.postid
),
question_tag_engagement as (
  select
    qt.tag,
    count(*) as q_count,
    avg(pm.engagement_score) as avg_engagement,
    sum(case when pm.has_duplicate_link then 1 else 0 end) as dup_count
  from question_tags qt
  join post_metrics pm on pm.id = qt.post_id and pm.posttypeid = 1
  group by qt.tag
),
tag_leaders as (
  select
    tp.tag,
    tp.tag_usage_count,
    tp.popularity_decile,
    qte.avg_engagement,
    qte.dup_count,
    row_number() over (order by tp.tag_usage_count desc, qte.avg_engagement desc nulls last) as rn_tag_global
  from tag_popularity tp
  left join question_tag_engagement qte on qte.tag = tp.tag
),
user_top_tags as (
  select
    p.owneruserid as user_id,
    qt.tag,
    count(*) as cnt,
    row_number() over (partition by p.owneruserid order by count(*) desc, min(p.creationdate)) as rn_tag_user
  from posts p
  join question_tags qt on qt.post_id = p.id
  where p.posttypeid = 1
  group by p.owneruserid, qt.tag
),
user_engagement_distribution as (
  select
    ua.user_id,
    ua.displayname,
    ua.reputation,
    ua.total_post_score,
    ua.total_views,
    ua.questions,
    ua.answers,
    -- move percentiles to an aggregated subquery to avoid ordered-set with OVER
    null as p50_score_all,
    null as p90_score_all,
    cume_dist() over (order by ua.total_post_score) as score_cume_dist,
    ntile(20) over (order by ua.total_post_score) as score_ventile
  from user_activity ua
),
user_score_percentiles as (
  select
    percentile_cont(0.5) within group (order by total_post_score) as p50_score_all,
    percentile_cont(0.9) within group (order by total_post_score) as p90_score_all
  from user_activity
),
user_post_summary as (
  select
    pmw.owneruserid as user_id,
    count(*) as posts_total,
    coalesce(sum(case when pmw.posttypeid = 1 then 1 else 0 end),0) as q_total,
    coalesce(sum(case when pmw.posttypeid = 2 then 1 else 0 end),0) as a_total,
    sum(pmw.engagement_score) as engagement_sum,
    avg(pmw.engagement_score) as engagement_avg,
    max(pmp.p90_engagement_user) as engagement_p90_est,
    max(case when pmw.rn_engagement_user = 1 then pmw.id end) as top_post_id,
    max(case when pmw.rn_engagement_user = 1 then pmw.engagement_score end) as top_post_engagement
  from post_metrics_windowed pmw
  left join post_metrics_user_percentiles pmp on pmp.user_id = pmw.owneruserid
  group by pmw.owneruserid
),
resurgent_users as (
  select
    uar.user_id,
    uar.displayname,
    uar.reputation,
    uar.last_post_activity,
    lag(uar.last_post_activity) over (order by uar.last_post_activity) as prev_activity_global,
    case
      when uar.last_post_activity is not null
           and uar.last_post_activity >= cast('2024-10-01 12:34:56' as timestamp) - interval '30 days'
           and (uar.user_created < cast('2024-10-01 12:34:56' as timestamp) - interval '365 days' or uar.reputation > 1000)
      then 1 else 0 end as is_resurgent
  from user_activity_ranked uar
),
user_avg_accept_secs as (
  select
    u.id as user_id,
    (
      select avg(extract(epoch from (pa.creationdate - pq.creationdate)))
      from posts pq
      join posts pa on pa.id = pq.acceptedanswerid
      where pq.owneruserid = u.id
        and pq.posttypeid = 1
    ) as avg_secs_to_accept
  from users u
)
select
  uar.user_id,
  uar.displayname,
  uar.reputation,
  uar.questions,
  uar.answers,
  uar.total_views,
  uar.total_post_score,
  uar.upvotes_given,
  uar.downvotes_given,
  uar.bounties_interactions,
  coalesce(ba.badges_total,0) as badges_total,
  coalesce(ba.gold_badges,0) as gold_badges,
  coalesce(ba.silver_badges,0) as silver_badges,
  coalesce(ba.bronze_badges,0) as bronze_badges,
  coalesce(ba.tag_badges,0) as tag_badges,
  ups.posts_total,
  ups.q_total,
  ups.a_total,
  ups.engagement_sum,
  ups.engagement_avg,
  ups.top_post_id,
  ups.top_post_engagement,
  ued.score_cume_dist,
  ued.score_ventile,
  utt.tag as top_user_tag,
  tl.popularity_decile as top_tag_popularity_decile,
  tl.tag_usage_count as top_tag_usage,
  tl.avg_engagement as top_tag_avg_engagement,
  ru.is_resurgent,
  uaa.avg_secs_to_accept,
  case
    when uar.rn_score <= 100 then 'Top-100 by score'
    when uar.rn_questions <= 100 then 'Top-100 by questions'
    when uar.rn_answers <= 100 then 'Top-100 by answers'
    when ued.score_ventile >= 19 then 'Top Ventiles'
    else 'Everyone Else'
  end as cohort_label,
  coalesce(tl.dup_count,0) as top_tag_dup_count,
  case
    when u.displayname is null or btrim(u.displayname) = '' then '(anon)'
    else substring(u.displayname from 1 for 1) || repeat('*', greatest(length(u.displayname)-2,0)) || substring(u.displayname from greatest(length(u.displayname),1) for 1)
  end as masked_display_name
from user_activity_ranked uar
join users u on u.id = uar.user_id
left join badge_agg ba on ba.userid = uar.user_id
left join user_post_summary ups on ups.user_id = uar.user_id
left join user_engagement_distribution ued on ued.user_id = uar.user_id
left join user_top_tags utt on utt.user_id = uar.user_id and utt.rn_tag_user = 1
left join tag_leaders tl on tl.tag = utt.tag
left join resurgent_users ru on ru.user_id = uar.user_id
left join user_avg_accept_secs uaa on uaa.user_id = uar.user_id
where
  (coalesce(uar.questions,0) + coalesce(uar.answers,0)) >= 5
  and (
    uar.total_post_score > 0
    or (ba.gold_badges is not null and ba.gold_badges >= 1)
    or (utt.tag is not null and tl.popularity_decile <= 3)
  )
  and (
    u.websiteurl is null
    or position('stackoverflow.com' in lower(coalesce(u.websiteurl,''))) > 0
    or (u.location is not null and length(u.location) > 10)
  )
  and (
    uar.last_post_activity is null
    or uar.last_post_activity >= uar.user_created
  )
order by
  cohort_label,
  uar.total_post_score desc nulls last,
  ups.engagement_avg desc nulls last
limit 500;