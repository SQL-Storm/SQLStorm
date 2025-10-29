with recent_activity as (
  select
    p.id as post_id,
    p.posttypeid,
    p.owneruserid,
    p.title,
    p.tags,
    p.score,
    p.viewcount,
    p.creationdate,
    p.lastactivitydate,
    coalesce(p.answercount, 0) as answercount,
    extract(epoch from (coalesce(p.lastactivitydate, cast('2024-10-01 12:34:56' as timestamp)) - p.creationdate)) / 3600.0 as age_hours
  from posts p
  where p.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '365 days'
),
user_stats as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    u.creationdate as user_created,
    u.location,
    u.websiteurl,
    coalesce(u.upvotes - u.downvotes, 0) as net_votes,
    coalesce(u.views, 0) as profile_views,
    count(distinct b.id) filter (where b.class = 1) as gold_badges,
    count(distinct b.id) filter (where b.class = 2) as silver_badges,
    count(distinct b.id) filter (where b.class = 3) as bronze_badges,
    max(b.date) as last_badge_date
  from users u
  left join badges b on b.userid = u.id
  group by u.id, u.displayname, u.reputation, u.creationdate, u.location, u.websiteurl, u.upvotes, u.downvotes, u.views
),
votes_agg as (
  select
    v.postid,
    sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
    sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
    sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites,
    sum(case when v.votetypeid in (8,9) then coalesce(v.bountyamount,0) else 0 end) as bounty_total,
    count(*) filter (where v.votetypeid in (10,11,12)) as mod_actions
  from votes v
  where v.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '365 days'
  group by v.postid
),
comment_activity as (
  select
    c.postid,
    count(*) as comment_count,
    max(c.creationdate) as last_comment_date,
    sum(case when c.score > 0 then 1 else 0 end) as positive_comments,
    sum(case when c.score < 0 then 1 else 0 end) as negative_comments
  from comments c
  where c.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '365 days'
  group by c.postid
),
ph_events as (
  select
    ph.postid,
    sum(case when ph.posthistorytypeid in (10) then 1 else 0 end) as close_votes,
    sum(case when ph.posthistorytypeid in (11) then 1 else 0 end) as reopen_votes,
    sum(case when ph.posthistorytypeid in (12) then 1 else 0 end) as delete_votes,
    sum(case when ph.posthistorytypeid in (13) then 1 else 0 end) as undelete_votes,
    sum(case when ph.posthistorytypeid in (19) then 1 else 0 end) as protect_events,
    sum(case when ph.posthistorytypeid in (20) then 1 else 0 end) as unprotect_events,
    max(ph.creationdate) as last_history_date
  from posthistory ph
  where ph.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '365 days'
  group by ph.postid
),
link_agg as (
  select
    pl.postid,
    sum(case when pl.linktypeid = 1 then 1 else 0 end) as linked_out,
    sum(case when pl.linktypeid = 3 then 1 else 0 end) as marked_duplicate_of
  from postlinks pl
  where pl.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '365 days'
  group by pl.postid
),
question_core as (
  select
    ra.*,
    case when ra.posttypeid = 1 then 1 else 0 end as is_question,
    case when ra.posttypeid = 2 then 1 else 0 end as is_answer,
    case
      when ra.tags is null then 0
      when length(ra.tags) < 2 then 0
      else 1 + length(ra.tags) - length(replace(ra.tags, '><', ''))
    end as tag_count
  from recent_activity ra
),
answers_per_question as (
  select
    q.id as question_id,
    count(a.id) as answers_last_year,
    max(a.score) as max_answer_score,
    avg(cast(a.score as numeric)) as avg_answer_score
  from posts q
  left join posts a
    on a.parentid = q.id
    and a.posttypeid = 2
    and a.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '365 days'
  where q.posttypeid = 1
    and q.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '365 days'
  group by q.id
),
accepted_lag as (
  select
    q.id as question_id,
    q.creationdate as question_created,
    a.creationdate as accepted_created,
    extract(epoch from (a.creationdate - q.creationdate))/3600.0 as hours_to_accept
  from posts q
  join posts a on a.id = q.acceptedanswerid
  where q.posttypeid = 1
    and q.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '365 days'
),
tag_exploded as (
  select
    p.id as post_id,
    unnest(string_to_array(substring(p.tags, 2, greatest(length(p.tags)-2,0)), '><')) as tagname
  from posts p
  where p.posttypeid = 1
    and p.tags is not null
    and p.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '365 days'
),
tag_rank as (
  select
    te.post_id,
    te.tagname,
    t.count as global_tag_count,
    row_number() over (partition by te.post_id order by coalesce(t.count,0) desc, te.tagname) as tag_rank_by_popularity
  from tag_exploded te
  left join tags t on lower(t.tagname) = lower(te.tagname)
),
primary_tag as (
  select
    post_id,
    min(tagname) filter (where tag_rank_by_popularity = 1) as primary_tagname,
    max(global_tag_count) filter (where tag_rank_by_popularity = 1) as primary_tag_popularity
  from tag_rank
  group by post_id
),
user_quality as (
  select
    us.user_id,
    percentile_cont(0.5) within group (order by p.score) as median_post_score_last_year,
    avg(cast(p.score as numeric)) as avg_post_score_last_year,
    count(*) as posts_last_year
  from user_stats us
  join posts p on p.owneruserid = us.user_id
  where p.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '365 days'
  group by us.user_id
),
post_engagement as (
  select
    qc.post_id,
    coalesce(va.upvotes,0) as upvotes,
    coalesce(va.downvotes,0) as downvotes,
    coalesce(va.favorites,0) as favorites,
    coalesce(va.bounty_total,0) as bounty_total,
    coalesce(ca.comment_count,0) as comment_count
  from question_core qc
  left join votes_agg va on va.postid = qc.post_id
  left join comment_activity ca on ca.postid = qc.post_id
),
scored as (
  select
    qc.post_id,
    qc.title,
    qc.tags,
    qc.posttypeid,
    qc.owneruserid,
    qc.creationdate,
    qc.lastactivitydate,
    qc.score,
    qc.viewcount,
    qc.answercount,
    qc.age_hours,
    qc.tag_count,
    coalesce(pe.upvotes,0) as upvotes,
    coalesce(pe.downvotes,0) as downvotes,
    coalesce(pe.favorites,0) as favorites,
    coalesce(pe.bounty_total,0) as bounty_total,
    coalesce(pe.comment_count,0) as comment_count,
    coalesce(ph.close_votes,0) as close_votes,
    coalesce(ph.reopen_votes,0) as reopen_votes,
    coalesce(ph.delete_votes,0) as delete_votes,
    coalesce(ph.protect_events,0) as protect_events,
    coalesce(la.linked_out,0) as linked_out,
    coalesce(la.marked_duplicate_of,0) as marked_duplicate_of,
    coalesce(al.hours_to_accept, null) as hours_to_accept,
    coalesce(apq.answers_last_year, 0) as answers_last_year,
    coalesce(apq.max_answer_score, 0) as max_answer_score,
    apq.avg_answer_score,
    pt.primary_tagname,
    pt.primary_tag_popularity,
    (
      0.40 * ln(1 + greatest(qc.viewcount,0)) +
      0.35 * (coalesce(pe.upvotes,0) - 0.5 * coalesce(pe.downvotes,0)) +
      0.15 * ln(1 + coalesce(pe.comment_count,0)) +
      0.10 * ln(1 + coalesce(pe.favorites,0)) +
      0.05 * ln(1 + coalesce(pe.bounty_total,0)) +
      0.05 * coalesce(apq.max_answer_score,0) -
      0.10 * coalesce(ph.close_votes,0) -
      0.15 * coalesce(ph.delete_votes,0)
    ) as engagement_score
  from question_core qc
  left join post_engagement pe on pe.post_id = qc.post_id
  left join ph_events ph on ph.postid = qc.post_id
  left join link_agg la on la.postid = qc.post_id
  left join accepted_lag al on al.question_id = qc.post_id
  left join answers_per_question apq on apq.question_id = qc.post_id
  left join primary_tag pt on pt.post_id = qc.post_id
),
user_enriched as (
  select
    s.post_id,
    s.title,
    s.tags,
    s.posttypeid,
    s.owneruserid,
    s.creationdate,
    s.lastactivitydate,
    s.score,
    s.viewcount,
    s.answercount,
    s.age_hours,
    s.tag_count,
    s.upvotes,
    s.downvotes,
    s.favorites,
    s.bounty_total,
    s.comment_count,
    s.close_votes,
    s.reopen_votes,
    s.delete_votes,
    s.protect_events,
    s.linked_out,
    s.marked_duplicate_of,
    s.hours_to_accept,
    s.answers_last_year,
    s.max_answer_score,
    s.avg_answer_score,
    s.primary_tagname,
    s.primary_tag_popularity,
    s.engagement_score,
    us.displayname as owner_displayname,
    us.reputation as owner_reputation,
    us.location as owner_location,
    uq.median_post_score_last_year,
    uq.avg_post_score_last_year,
    uq.posts_last_year,
    us.gold_badges,
    us.silver_badges,
    us.bronze_badges,
    us.last_badge_date
  from scored s
  left join user_stats us on us.user_id = s.owneruserid
  left join user_quality uq on uq.user_id = s.owneruserid
),
ranked as (
  select
    ue.post_id,
    ue.title,
    ue.tags,
    ue.posttypeid,
    ue.owneruserid,
    ue.creationdate,
    ue.lastactivitydate,
    ue.score,
    ue.viewcount,
    ue.answercount,
    ue.age_hours,
    ue.tag_count,
    ue.upvotes,
    ue.downvotes,
    ue.favorites,
    ue.bounty_total,
    ue.comment_count,
    ue.close_votes,
    ue.reopen_votes,
    ue.delete_votes,
    ue.protect_events,
    ue.linked_out,
    ue.marked_duplicate_of,
    ue.hours_to_accept,
    ue.answers_last_year,
    ue.max_answer_score,
    ue.avg_answer_score,
    ue.primary_tagname,
    ue.primary_tag_popularity,
    ue.engagement_score,
    ue.owner_displayname,
    ue.owner_reputation,
    ue.owner_location,
    ue.median_post_score_last_year,
    ue.avg_post_score_last_year,
    ue.posts_last_year,
    ue.gold_badges,
    ue.silver_badges,
    ue.bronze_badges,
    ue.last_badge_date,
    row_number() over (
      partition by coalesce(ue.primary_tagname, 'zzzz_no_tag')
      order by ue.engagement_score desc NULLS LAST, ue.score desc NULLS LAST, ue.viewcount desc NULLS LAST
    ) as rank_in_tag,
    ntile(10) over (order by ue.engagement_score desc NULLS LAST) as decile_overall,
    dense_rank() over (order by coalesce(ue.owner_reputation, -1) desc) as owner_rep_rank
  from user_enriched ue
),
null_logic_demo as (
  select
    r.post_id,
    r.title,
    r.tags,
    r.posttypeid,
    r.owneruserid,
    r.creationdate,
    r.lastactivitydate,
    r.score,
    r.viewcount,
    r.answercount,
    r.age_hours,
    r.tag_count,
    r.upvotes,
    r.downvotes,
    r.favorites,
    r.bounty_total,
    r.comment_count,
    r.close_votes,
    r.reopen_votes,
    r.delete_votes,
    r.protect_events,
    r.linked_out,
    r.marked_duplicate_of,
    r.hours_to_accept,
    r.answers_last_year,
    r.max_answer_score,
    r.avg_answer_score,
    r.primary_tagname,
    r.primary_tag_popularity,
    r.engagement_score,
    r.owner_displayname,
    r.owner_reputation,
    r.owner_location,
    r.median_post_score_last_year,
    r.avg_post_score_last_year,
    r.posts_last_year,
    r.gold_badges,
    r.silver_badges,
    r.bronze_badges,
    r.last_badge_date,
    coalesce(r.hours_to_accept, case when r.answers_last_year > 0 then 48.0 / greatest(r.answers_last_year,1) else 1e9 end) as resolution_proxy,
    trim(both from regexp_replace(coalesce(r.title,''), '\s+', ' ', 'g')) as title_normalized,
    (
      (r.posttypeid = 1 and r.answercount >= 1)
      and (r.engagement_score > 1.0 or (r.upvotes - r.downvotes) >= 3 or r.viewcount >= 1000)
      and not ((r.close_votes >= 1 and r.delete_votes >= 1) or r.marked_duplicate_of >= 2)
    ) as is_interesting,
    r.rank_in_tag,
    r.decile_overall,
    r.owner_rep_rank
  from ranked r
),
topn as (
  select *
  from null_logic_demo
  where is_interesting
    and coalesce(primary_tagname,'') <> ''
    and coalesce(owner_reputation,0) >= 1
),
topn_with_limits as (
  select
    t.post_id,
    t.title_normalized as title,
    t.primary_tagname as tag,
    t.primary_tag_popularity,
    t.owneruserid,
    t.owner_displayname,
    t.owner_reputation,
    t.owner_location,
    t.score,
    t.viewcount,
    t.answercount,
    t.upvotes,
    t.downvotes,
    t.favorites,
    t.comment_count,
    t.bounty_total,
    t.engagement_score,
    t.decile_overall,
    t.rank_in_tag,
    t.owner_rep_rank,
    t.answers_last_year,
    t.max_answer_score,
    round(cast(t.avg_answer_score as numeric),2) as avg_answer_score,
    t.hours_to_accept,
    t.resolution_proxy,
    t.close_votes,
    t.reopen_votes,
    t.delete_votes,
    t.protect_events,
    t.linked_out,
    t.marked_duplicate_of,
    t.tag_count,
    t.creationdate,
    t.lastactivitydate,
    t.last_badge_date
  from topn t
  where t.rank_in_tag <= 5
)
select *
from topn_with_limits
order by decile_overall asc, rank_in_tag asc, engagement_score desc, post_id asc;