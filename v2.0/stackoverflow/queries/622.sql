with recent_users as (
  select
    u.id,
    u.displayname,
    u.reputation,
    u.location,
    u.creationdate,
    u.upvotes,
    u.downvotes,
    row_number() over (partition by coalesce(nullif(trim(lower(u.location)), ''), 'unknown') order by u.reputation desc, u.id) as rn_loc
  from users u
  where u.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '5 years'
),
active_posts as (
  select
    p.id,
    p.posttypeid,
    p.owneruserid,
    p.creationdate,
    p.score,
    p.viewcount,
    p.answercount,
    p.commentcount,
    p.title,
    p.tags,
    p.closeddate,
    case when p.closeddate is null then 0 else 1 end as is_closed,
    coalesce(p.viewcount, 0) / nullif(date_part('day', cast('2024-10-01 12:34:56' as timestamp) - p.creationdate), 0) as views_per_day
  from posts p
  where p.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '5 years'
    and p.posttypeid in (1,2)
),
tag_splits as (
  select
    ap.id as post_id,
    unnest(string_to_array(substring(ap.tags, 2, greatest(length(ap.tags)-2,0)), '><')) as tag
  from active_posts ap
  where ap.posttypeid = 1
    and ap.tags is not null
),
tag_activity as (
  select
    ts.tag,
    count(distinct ts.post_id) as question_count_5y,
    percentile_cont(0.5) within group (order by ap.score) as median_score,
    avg(ap.viewcount) as avg_views,
    sum(coalesce(ap.answercount,0)) as total_answers
  from tag_splits ts
  join active_posts ap on ap.id = ts.post_id
  group by ts.tag
),
user_badge_summary as (
  select
    b.userid,
    sum(case when b.class = 1 then 1 else 0 end) as gold_count,
    sum(case when b.class = 2 then 1 else 0 end) as silver_count,
    sum(case when b.class = 3 then 1 else 0 end) as bronze_count,
    sum(case when b.tagbased = true then 1 else 0 end) as tag_badges
  from badges b
  where b.date >= cast('2024-10-01 12:34:56' as timestamp) - interval '5 years'
  group by b.userid
),
post_vote_agg as (
  select
    v.postid,
    sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
    sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
    sum(case when v.votetypeid in (8,9) then coalesce(v.bountyamount,0) else 0 end) as total_bounty
  from votes v
  where v.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '5 years'
  group by v.postid
),
dup_links as (
  select
    pl.postid as dup_post_id,
    pl.relatedpostid as original_post_id,
    min(pl.creationdate) as first_dup_date
  from postlinks pl
  where pl.linktypeid = 3
  group by pl.postid, pl.relatedpostid
),
edit_bursts as (
  select
    ph.postid,
    count(*) filter (where ph.posthistorytypeid in (4,5,6)) as edit_count,
    max(ph.creationdate) as last_edit_date,
    min(ph.creationdate) as first_edit_date
  from posthistory ph
  where ph.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '5 years'
  group by ph.postid
),
question_core as (
  select
    ap.*,
    pv.upvotes,
    pv.downvotes,
    pv.total_bounty,
    eb.edit_count,
    eb.last_edit_date,
    case
      when ap.answercount is null then 0
      when ap.answercount = 0 and ap.score > 0 then 0.25
      when ap.answercount = 0 and ap.score <= 0 then 0.1
      else ap.answercount
    end as adjusted_answercount,
    case when dl.original_post_id is not null then 1 else 0 end as is_duplicate
  from active_posts ap
  left join post_vote_agg pv on pv.postid = ap.id
  left join edit_bursts eb on eb.postid = ap.id
  left join dup_links dl on dl.dup_post_id = ap.id
  where ap.posttypeid = 1
),
author_quality as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    coalesce(ubs.gold_count,0) as gold_badges,
    coalesce(ubs.silver_count,0) as silver_badges,
    coalesce(ubs.bronze_count,0) as bronze_badges,
    coalesce(ubs.tag_badges,0) as tag_badges,
    u.upvotes - u.downvotes as net_votes,
    dense_rank() over (order by u.reputation desc) as rep_rank
  from recent_users u
  left join user_badge_summary ubs on ubs.userid = u.id
),
author_post_stats as (
  select
    qc.owneruserid as user_id,
    count(*) as q_count,
    avg(qc.score) as avg_q_score,
    avg(coalesce(qc.viewcount,0)) as avg_q_views,
    sum(coalesce(qc.total_bounty,0)) as sum_q_bounty,
    sum(case when qc.is_duplicate = 1 then 1 else 0 end) as dup_qs
  from question_core qc
  group by qc.owneruserid
),
question_enriched as (
  select
    qc.id,
    qc.title,
    qc.tags,
    qc.creationdate,
    qc.score,
    qc.viewcount,
    qc.adjusted_answercount,
    qc.upvotes,
    qc.downvotes,
    qc.total_bounty,
    qc.is_closed,
    qc.is_duplicate,
    qc.views_per_day,
    qc.owneruserid,
    aq.reputation,
    aq.gold_badges,
    aq.silver_badges,
    aq.bronze_badges,
    aq.tag_badges,
    aps.q_count as author_q_count,
    aps.avg_q_score as author_avg_q_score,
    aps.avg_q_views as author_avg_q_views,
    aps.sum_q_bounty as author_sum_q_bounty,
    aps.dup_qs as author_dup_qs,
    coalesce(qc.edit_count,0) as edit_count,
    qc.last_edit_date
  from question_core qc
  left join author_quality aq on aq.user_id = qc.owneruserid
  left join author_post_stats aps on aps.user_id = qc.owneruserid
),
question_tag_score as (
  select
    qe.id as question_id,
    avg(coalesce(ta.median_score, 0)) as tag_median_score,
    sum(coalesce(ta.total_answers, 0)) as tag_total_answers,
    min(coalesce(ta.avg_views, 0)) as min_tag_avg_views
  from question_enriched qe
  left join tag_splits ts on ts.post_id = qe.id
  left join tag_activity ta on ta.tag = ts.tag
  group by qe.id
),
scored as (
  select
    qe.*,
    qts.tag_median_score,
    qts.tag_total_answers,
    qts.min_tag_avg_views,
    (
      0.30 * coalesce(qe.score, 0) +
      0.15 * coalesce(qe.views_per_day, 0) +
      0.10 * ln(1 + greatest(coalesce(qe.total_bounty,0),0)) +
      0.10 * coalesce(qts.tag_median_score, 0) +
      0.10 * coalesce(qe.reputation, 0) / nullif((select avg(reputation) from recent_users), 0) +
      0.05 * coalesce(qe.gold_badges, 0) +
      0.05 * case when qe.is_duplicate = 1 then -5 else 0 end +
      0.05 * case when qe.is_closed = 1 then -10 else 0 end +
      0.10 * coalesce(qe.adjusted_answercount,0)
    ) as composite_score
  from question_enriched qe
  left join question_tag_score qts on qts.question_id = qe.id
),
ranked as (
  select
    s.*,
    row_number() over (order by s.composite_score desc nulls last, s.viewcount desc nulls last) as rn_global,
    rank() over (partition by case when s.tags like '%<sql>%' then 'sql' else 'other' end order by s.composite_score desc nulls last) as rn_sql_partition,
    ntile(20) over (order by s.composite_score desc nulls last) as vigintile
  from scored s
),
activity_blend as (
  select
    r.id,
    r.owneruserid,
    coalesce(r.composite_score,0) as composite_score,
    coalesce(r.viewcount,0) as viewcount,
    coalesce(r.upvotes,0) as upvotes,
    coalesce(r.downvotes,0) as downvotes,
    coalesce(r.total_bounty,0) as total_bounty,
    coalesce(r.edit_count,0) as edit_count,
    r.rn_global,
    r.rn_sql_partition,
    r.vigintile,
    (
      select count(*)
      from comments c
      where c.postid = r.id
        and c.creationdate >= r.creationdate
        and c.creationdate < r.creationdate + interval '30 days'
    ) as comments_30d,
    (
      select avg(coalesce(score,0))
      from comments c
      where c.postid = r.id
    ) as avg_comment_score,
    r.creationdate
  from ranked r
),
with_flags as (
  select
    ab.id,
    ab.owneruserid,
    ab.composite_score,
    ab.viewcount,
    ab.upvotes,
    ab.downvotes,
    ab.total_bounty,
    ab.edit_count,
    ab.rn_global,
    ab.rn_sql_partition,
    ab.vigintile,
    ab.comments_30d,
    ab.avg_comment_score,
    ab.creationdate,
    case when ab.comments_30d > 10 and ab.vigintile <= 5 then 1 else 0 end as trending_flag,
    case when ab.avg_comment_score < 0 and ab.downvotes > ab.upvotes then 1 else 0 end as controversial_flag
  from activity_blend ab
),
final_set as (
  select
    wf.id,
    wf.owneruserid,
    wf.composite_score,
    wf.viewcount,
    wf.upvotes,
    wf.downvotes,
    wf.total_bounty,
    wf.edit_count,
    wf.rn_global,
    wf.rn_sql_partition,
    wf.vigintile,
    wf.comments_30d,
    wf.avg_comment_score,
    wf.trending_flag,
    wf.controversial_flag
  from with_flags wf
  where wf.vigintile <= 10
  union all
  select
    wf.id,
    wf.owneruserid,
    wf.composite_score,
    wf.viewcount,
    wf.upvotes,
    wf.downvotes,
    wf.total_bounty,
    wf.edit_count,
    wf.rn_global,
    wf.rn_sql_partition,
    wf.vigintile,
    wf.comments_30d,
    wf.avg_comment_score,
    wf.trending_flag,
    wf.controversial_flag
  from with_flags wf
  where wf.trending_flag = 1
)
select
  fs.id as post_id,
  coalesce(u.displayname, ('user#' || cast(fs.owneruserid as text))) as author,
  u.reputation,
  fs.composite_score,
  fs.viewcount,
  fs.upvotes,
  fs.downvotes,
  fs.total_bounty,
  fs.edit_count,
  fs.rn_global,
  fs.rn_sql_partition,
  fs.vigintile,
  fs.comments_30d,
  fs.avg_comment_score,
  fs.trending_flag,
  fs.controversial_flag,
  case
    when u.websiteurl is null or trim(u.websiteurl) = '' then '(no-site)'
    when position('http' in lower(u.websiteurl)) = 1 then u.websiteurl
    else ('https://' || u.websiteurl)
  end as normalized_website,
  case
    when coalesce(u.reputation,0) >= 100000 then 'legend'
    when coalesce(u.reputation,0) >= 25000 then 'expert'
    when coalesce(u.reputation,0) >= 5000 then 'advanced'
    else 'regular'
  end as author_tier
from final_set fs
left join users u on u.id = fs.owneruserid
where fs.composite_score is not null
order by fs.composite_score desc, fs.rn_global asc
limit 500;