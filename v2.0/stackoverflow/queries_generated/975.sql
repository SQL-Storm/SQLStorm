-- {"query": "975.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3401} 
with recent_users as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    u.creationdate,
    u.location,
    u.upvotes,
    u.downvotes,
    u.views,
    coalesce(nullif(trim(split_part(coalesce(u.websiteurl, ''), '/', 3)), ''), 'none') as website_host
  from users u
  where u.creationdate >= (select date_trunc('month', max(creationdate)) - interval '12 months' from users)
),
user_badge_rollup as (
  select
    b.userid,
    sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
    sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
    sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
    count(*) as total_badges,
    max(b.date) as last_badge_date
  from badges b
  group by b.userid
),
user_post_activity as (
  select
    p.owneruserid as user_id,
    count(*) filter (where p.posttypeid = 1) as q_count,
    count(*) filter (where p.posttypeid = 2) as a_count,
    sum(coalesce(p.score,0)) as total_post_score,
    avg(nullif(p.viewcount,0)) as avg_views_nonzero,
    max(p.lastactivitydate) as last_post_activity,
    sum(case when p.closeddate is not null then 1 else 0 end) as closed_posts,
    sum(case when p.communityowneddate is not null then 1 else 0 end) as community_owned_posts
  from posts p
  where p.owneruserid is not null
  group by p.owneruserid
),
user_comment_activity as (
  select
    c.userid as user_id,
    count(*) as comment_count,
    sum(coalesce(c.score,0)) as comment_score,
    max(c.creationdate) as last_comment_date
  from comments c
  where c.userid is not null
  group by c.userid
),
user_vote_agg as (
  select
    v.userid as user_id,
    count(*) filter (where v.votetypeid = 2) as upmods,
    count(*) filter (where v.votetypeid = 3) as downmods,
    count(*) filter (where v.votetypeid = 5) as favorites,
    count(*) filter (where v.votetypeid in (8,9)) as bounty_events,
    sum(coalesce(case when v.votetypeid in (8,9) then v.bountyamount end, 0)) as bounty_amount_total,
    max(v.creationdate) as last_vote_date
  from votes v
  where v.userid is not null
  group by v.userid
),
question_tag_counts as (
  select
    p.id as question_id,
    coalesce(array_length(string_to_array(substring(p.tags, 2, length(p.tags)-2), '><'), 1), 0) as tag_count
  from posts p
  where p.posttypeid = 1
),
answer_accepts as (
  select
    q.owneruserid as question_owner_id,
    a.owneruserid as answer_owner_id,
    count(*) as accepted_answers_authored
  from posts q
  join posts a on a.id = q.acceptedanswerid
  where q.posttypeid = 1
  group by q.owneruserid, a.owneruserid
),
user_accept_stats as (
  select
    aa.answer_owner_id as user_id,
    sum(aa.accepted_answers_authored) as accepted_answers_authored,
    sum(case when aa.question_owner_id = aa.answer_owner_id then aa.accepted_answers_authored else 0 end) as self_accepts
  from answer_accepts aa
  group by aa.answer_owner_id
),
hot_history as (
  select
    ph.postid,
    min(ph.creationdate) filter (where ph.posthistorytypeid = 52) as first_hot_date,
    max(ph.creationdate) filter (where ph.posthistorytypeid = 53) as last_unhot_date,
    count(*) filter (where ph.posthistorytypeid = 52) as times_hot,
    count(*) filter (where ph.posthistorytypeid = 53) as times_unhot
  from posthistory ph
  where ph.posthistorytypeid in (52,53)
  group by ph.postid
),
dup_links as (
  select
    pl.postid,
    count(*) filter (where pl.linktypeid = 3) as duplicate_links
  from postlinks pl
  group by pl.postid
),
question_quality as (
  select
    q.id as question_id,
    q.owneruserid as user_id,
    q.score,
    q.viewcount,
    q.favoritecount,
    qc.tag_count,
    coalesce(dl.duplicate_links,0) as duplicate_links,
    coalesce(hh.times_hot,0) as times_hot,
    case when q.closeddate is not null then 1 else 0 end as is_closed
  from posts q
  left join question_tag_counts qc on qc.question_id = q.id
  left join dup_links dl on dl.postid = q.id
  left join hot_history hh on hh.postid = q.id
  where q.posttypeid = 1
),
user_question_quality as (
  select
    qq.user_id,
    count(*) as q_total,
    avg(qq.score) as q_avg_score,
    percentile_cont(0.5) within group (order by qq.score) as q_median_score,
    avg(qq.viewcount) as q_avg_views,
    avg(qq.favoritecount) as q_avg_favs,
    avg(qq.tag_count) as q_avg_tags,
    sum(qq.duplicate_links) as q_dup_links_total,
    sum(qq.times_hot) as q_times_hot_total,
    sum(qq.is_closed) as q_closed_total
  from question_quality qq
  group by qq.user_id
),
recent_activity as (
  select
    u.id as user_id,
    max(x.last_date) as last_activity_any
  from users u
  left join lateral (
    select max(d) as last_date
    from (
      values
        (u.creationdate),
        ((select max(p.lastactivitydate) from posts p where p.owneruserid = u.id)),
        ((select max(c.creationdate) from comments c where c.userid = u.id)),
        ((select max(v.creationdate) from votes v where v.userid = u.id)),
        ((select max(b.date) from badges b where b.userid = u.id))
    ) as t(d)
  ) x on true
  group by u.id
),
activity_window as (
  select
    u.id as user_id,
    p.posttypeid,
    p.id as post_id,
    p.creationdate,
    count(*) over (partition by u.id) as total_items_window,
    row_number() over (partition by u.id order by p.creationdate desc nulls last) as rn_desc,
    row_number() over (partition by u.id order by p.creationdate asc nulls first) as rn_asc
  from users u
  left join posts p on p.owneruserid = u.id
  where p.creationdate >= coalesce((select date_trunc('year', max(creationdate)) - interval '1 year' from posts), timestamp 'epoch')
),
top_recent_posts as (
  select
    aw.user_id,
    string_agg(cast(aw.post_id as varchar), ',' order by aw.creationdate desc) filter (where aw.rn_desc <= 5) as last_5_post_ids,
    string_agg(cast(aw.post_id as varchar), ',' order by aw.creationdate asc) filter (where aw.rn_asc <= 5) as first_5_post_ids
  from activity_window aw
  group by aw.user_id
),
user_tag_affinity as (
  select
    q.owneruserid as user_id,
    unnest(string_to_array(substring(q.tags, 2, length(q.tags)-2), '><')) as tag_name
  from posts q
  where q.posttypeid = 1 and q.tags is not null
),
user_tag_rank as (
  select
    uta.user_id,
    uta.tag_name,
    count(*) as tag_uses,
    row_number() over (partition by uta.user_id order by count(*) desc, uta.tag_name) as tag_rank
  from user_tag_affinity uta
  group by uta.user_id, uta.tag_name
),
best_three_tags as (
  select
    user_id,
    string_agg(tag_name, ',' order by tag_rank) as top3_tags
  from user_tag_rank
  where tag_rank <= 3
  group by user_id
),
score_outliers as (
  select
    p.owneruserid as user_id,
    p.id as post_id,
    p.score,
    avg(p.score) over (partition by p.owneruserid) as user_avg_score,
    stddev_pop(p.score) over (partition by p.owneruserid) as user_std_score,
    case
      when stddev_pop(p.score) over (partition by p.owneruserid) > 0
        then (p.score - avg(p.score) over (partition by p.owneruserid)) / nullif(stddev_pop(p.score) over (partition by p.owneruserid), 0)
      else null
    end as zscore
  from posts p
  where p.owneruserid is not null and p.posttypeid in (1,2)
),
user_outlier_stats as (
  select
    so.user_id,
    max(abs(so.zscore)) as max_abs_z,
    count(*) filter (where so.zscore > 2) as high_outliers,
    count(*) filter (where so.zscore < -2) as low_outliers
  from score_outliers so
  group by so.user_id
),
user_null_logic as (
  select
    u.id as user_id,
    case
      when coalesce(trim(u.displayname), '') = '' then 1 else 0
    end as has_blank_displayname,
    case
      when u.location is null or trim(u.location) = '' then 'unknown'
      when position(',' in u.location) > 0 then split_part(u.location, ',', 1)
      else u.location
    end as normalized_location
  from users u
),
q_vs_a_ratio as (
  select
    u.id as user_id,
    case
      when coalesce(a.a_count,0) = 0 and coalesce(pa.q_count,0) = 0 then null
      when coalesce(a.a_count,0) = 0 then 9999.0
      else cast(coalesce(pa.q_count,0) as numeric) / nullif(a.a_count,0)
    end as q_to_a_ratio
  from users u
  left join user_post_activity pa on pa.user_id = u.id
  left join lateral (select coalesce(pa.a_count,0) as a_count) a on true
),
final as (
  select
    ru.user_id,
    ru.displayname,
    ru.reputation,
    ru.creationdate,
    ru.location,
    ru.website_host,
    coalesce(uba.gold_badges,0) as gold_badges,
    coalesce(uba.silver_badges,0) as silver_badges,
    coalesce(uba.bronze_badges,0) as bronze_badges,
    coalesce(uba.total_badges,0) as total_badges,
    uba.last_badge_date,
    coalesce(upa.q_count,0) as q_count,
    coalesce(upa.a_count,0) as a_count,
    coalesce(upa.total_post_score,0) as total_post_score,
    upa.avg_views_nonzero,
    upa.last_post_activity,
    coalesce(upa.closed_posts,0) as closed_posts,
    coalesce(upa.community_owned_posts,0) as community_owned_posts,
    coalesce(uca.comment_count,0) as comment_count,
    coalesce(uca.comment_score,0) as comment_score,
    uca.last_comment_date,
    coalesce(uva.upmods,0) as upmods,
    coalesce(uva.downmods,0) as downmods,
    coalesce(uva.favorites,0) as favorites,
    coalesce(uva.bounty_events,0) as bounty_events,
    coalesce(uva.bounty_amount_total,0) as bounty_amount_total,
    uva.last_vote_date,
    rq.last_activity_any,
    tq.q_total,
    tq.q_avg_score,
    tq.q_median_score,
    tq.q_avg_views,
    tq.q_avg_favs,
    tq.q_avg_tags,
    tq.q_dup_links_total,
    tq.q_times_hot_total,
    tq.q_closed_total,
    trp.last_5_post_ids,
    trp.first_5_post_ids,
    b3.top3_tags,
    uos.max_abs_z,
    uos.high_outliers,
    uos.low_outliers,
    unl.has_blank_displayname,
    unl.normalized_location,
    qar.q_to_a_ratio,
    uas.accepted_answers_authored,
    uas.self_accepts,
    case
      when coalesce(upa.q_count,0) + coalesce(upa.a_count,0) + coalesce(uca.comment_count,0) = 0 then 'inactive'
      when coalesce(upa.total_post_score,0) >= 1000 or coalesce(uba.gold_badges,0) >= 3 then 'elite'
      when coalesce(upa.total_post_score,0) >= 200 or coalesce(uba.silver_badges,0) >= 5 then 'active'
      else 'casual'
    end as activity_tier
  from recent_users ru
  left join user_badge_rollup uba on uba.userid = ru.user_id
  left join user_post_activity upa on upa.user_id = ru.user_id
  left join user_comment_activity uca on uca.user_id = ru.user_id
  left join user_vote_agg uva on uva.user_id = ru.user_id
  left join recent_activity rq on rq.user_id = ru.user_id
  left join user_question_quality tq on tq.user_id = ru.user_id
  left join top_recent_posts trp on trp.user_id = ru.user_id
  left join best_three_tags b3 on b3.user_id = ru.user_id
  left join user_outlier_stats uos on uos.user_id = ru.user_id
  left join user_null_logic unl on unl.user_id = ru.user_id
  left join q_vs_a_ratio qar on qar.user_id = ru.user_id
  left join user_accept_stats uas on uas.user_id = ru.user_id
)
select
  f.*,
  rank() over (order by coalesce(f.reputation,0) desc, coalesce(f.total_post_score,0) desc) as rep_rank,
  dense_rank() over (order by coalesce(f.q_avg_score, -1) desc nulls last) as avg_q_score_rank,
  row_number() over (partition by f.activity_tier order by coalesce(f.total_badges,0) desc, coalesce(f.total_post_score,0) desc) as tier_rownum
from final f
where
  (
    f.activity_tier <> 'inactive'
    or (f.last_activity_any is not null and f.last_activity_any >= now() - interval '365 days')
  )
  and (
    f.normalized_location ilike '%united%' or f.website_host not in ('none') or coalesce(f.top3_tags,'') <> ''
  )
  and (
    coalesce(f.q_to_a_ratio, 0) >= 0
    or (f.q_count > 0 and f.a_count = 0)
  )
order by
  rep_rank,
  tier_rownum
limit 500;