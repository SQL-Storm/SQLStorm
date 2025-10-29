with recent_users as (
  select u.id as user_id,
         u.displayname,
         u.reputation,
         u.creationdate,
         u.location,
         u.websiteurl,
         coalesce(nullif(trim(u.location), ''), 'Unknown') as norm_location
  from users u
  where u.creationdate >= (select date_trunc('month', max(creationdate)) - interval '24 months' from users)
),
user_activity as (
  select p.owneruserid as user_id,
         count(*) filter (where p.posttypeid = 1) as q_count,
         count(*) filter (where p.posttypeid = 2) as a_count,
         sum(coalesce(p.score,0)) as total_post_score,
         sum(coalesce(p.viewcount,0)) as total_views,
         min(p.creationdate) as first_post_date,
         max(p.lastactivitydate) as last_activity_date
  from posts p
  where p.owneruserid is not null
  group by p.owneruserid
),
user_comments as (
  select c.userid as user_id,
         count(*) as comment_count,
         sum(coalesce(c.score,0)) as comment_score,
         max(c.creationdate) as last_comment_date,
         avg(length(c.text)) as avg_comment_len
  from comments c
  where c.userid is not null
  group by c.userid
),
user_votes as (
  select v.userid as user_id,
         count(*) filter (where v.votetypeid = 2) as upvotes_cast,
         count(*) filter (where v.votetypeid = 3) as downvotes_cast,
         count(*) filter (where v.votetypeid = 8) as bounties_started,
         count(*) filter (where v.votetypeid = 9) as bounties_awarded,
         sum(case when v.votetypeid in (8,9) then coalesce(v.bountyamount,0) else 0 end) as total_bounty_amount,
         max(v.creationdate) as last_vote_date
  from votes v
  where v.userid is not null
  group by v.userid
),
user_badges as (
  select b.userid as user_id,
         count(*) as badges_total,
         count(*) filter (where b.class = 1) as gold_badges,
         count(*) filter (where b.class = 2) as silver_badges,
         count(*) filter (where b.class = 3) as bronze_badges,
         count(distinct b.name) as distinct_badges,
         sum(case when b.tagbased = true then 1 else 0 end) as tag_badges,
         max(b.date) as last_badge_date
  from badges b
  group by b.userid
),
question_metrics as (
  select p.owneruserid as user_id,
         count(*) as questions_total,
         sum(case when p.acceptedanswerid is not null then 1 else 0 end) as questions_with_accepted,
         avg(nullif(p.answercount,0)) as avg_answercount_nonzero,
         avg(coalesce(p.viewcount,0)) as avg_q_views,
         percentile_cont(0.9) within group (order by coalesce(p.viewcount,0)) as p90_q_views
  from posts p
  where p.posttypeid = 1 and p.owneruserid is not null
  group by p.owneruserid
),
answer_metrics as (
  select p.owneruserid as user_id,
         count(*) as answers_total,
         sum(case when exists (
           select 1 from posts q
           where q.id = p.parentid and q.acceptedanswerid = p.id
         ) then 1 else 0 end) as accepted_answers,
         avg(coalesce(p.score,0)) as avg_answer_score
  from posts p
  where p.posttypeid = 2 and p.owneruserid is not null
  group by p.owneruserid
),
post_linking as (
  select pl.postid,
         pl.relatedpostid,
         pl.linktypeid
  from postlinks pl
),
dup_pairs as (
  select pl.postid as dup_id,
         pl.relatedpostid as original_id
  from post_linking pl
  where pl.linktypeid = 3
),
user_duplicates as (
  select coalesce(p.owneruserid, q.owneruserid) as user_id,
         count(*) as duplicate_links_count,
         count(distinct case when p.posttypeid = 1 then p.id end) as dup_questions_authored,
         count(distinct case when q.posttypeid = 1 then q.id end) as original_questions_referenced
  from dup_pairs d
  join posts p on p.id = d.dup_id
  join posts q on q.id = d.original_id
  group by coalesce(p.owneruserid, q.owneruserid)
),
post_edits as (
  select ph.postid,
         ph.userid,
         count(*) filter (where ph.posthistorytypeid in (4,5,6)) as edit_count,
         max(ph.creationdate) as last_edit_date,
         sum(case when ph.posthistorytypeid in (10,35) then 1 else 0 end) as close_or_migrate_events
  from posthistory ph
  group by ph.postid, ph.userid
),
user_edits as (
  select pe.userid as user_id,
         sum(pe.edit_count) as total_edits_made,
         max(pe.last_edit_date) as last_edit_made,
         sum(pe.close_or_migrate_events) as close_migrate_events_touched
  from post_edits pe
  where pe.userid is not null
  group by pe.userid
),
tag_extract as (
  select p.id as post_id,
         p.owneruserid as user_id,
         unnest(string_to_array(substring(p.tags, 2, length(p.tags)-2), '><')) as tag
  from posts p
  where p.posttypeid = 1 and p.tags is not null and p.owneruserid is not null
),
user_top_tags as (
  select user_id,
         tag,
         count(*) as tag_uses,
         row_number() over (partition by user_id order by count(*) desc, tag) as rn
  from tag_extract
  group by user_id, tag
),
user_top3_tags as (
  select user_id,
         string_agg(tag || ':' || cast(tag_uses as text), ', ' order by rn) as top3_tags
  from user_top_tags
  where rn <= 3
  group by user_id
),
activity_union as (
  select ua.user_id,
         ua.q_count + ua.a_count as posts_authored,
         ua.total_post_score as score_total,
         ua.total_views as views_total,
         ua.last_activity_date as last_activity
  from user_activity ua
  union all
  select uc.user_id,
         uc.comment_count,
         uc.comment_score,
         null as views_total,
         uc.last_comment_date
  from user_comments uc
  union all
  select uv.user_id,
         uv.upvotes_cast + uv.downvotes_cast,
         uv.total_bounty_amount,
         null as views_total,
         uv.last_vote_date
  from user_votes uv
),
activity_rank as (
  select user_id,
         sum(coalesce(posts_authored,0)) as agg_events,
         sum(coalesce(score_total,0)) as agg_score_like,
         max(last_activity) as last_activity_any
  from activity_union
  group by user_id
),
user_recency as (
  select ru.user_id,
         cast(date_part('day', cast('2024-10-01 12:34:56' as timestamp) - coalesce(ar.last_activity_any, ru.creationdate)) as integer) as days_since_seen,
         case
           when cast('2024-10-01 12:34:56' as timestamp) - coalesce(ar.last_activity_any, ru.creationdate) < interval '30 days' then 'Active-30'
           when cast('2024-10-01 12:34:56' as timestamp) - coalesce(ar.last_activity_any, ru.creationdate) < interval '90 days' then 'Active-90'
           when cast('2024-10-01 12:34:56' as timestamp) - coalesce(ar.last_activity_any, ru.creationdate) < interval '365 days' then 'Dormant-1y'
           else 'Dormant-1y+'
         end as activity_bucket
  from recent_users ru
  left join activity_rank ar on ar.user_id = ru.user_id
),
final_scores as (
  select ru.user_id,
         ru.displayname,
         ru.reputation,
         ru.norm_location,
         coalesce(ua.q_count,0) as q_count,
         coalesce(ua.a_count,0) as a_count,
         coalesce(qm.questions_with_accepted,0) as q_with_accepted,
         coalesce(am.accepted_answers,0) as accepted_answers,
         coalesce(qm.avg_q_views,0) as avg_q_views,
         coalesce(am.avg_answer_score,0) as avg_answer_score,
         coalesce(ub.badges_total,0) as badges_total,
         coalesce(ub.gold_badges,0) as gold_badges,
         coalesce(ub.silver_badges,0) as silver_badges,
         coalesce(ub.bronze_badges,0) as bronze_badges,
         coalesce(ud.duplicate_links_count,0) as duplicate_links_count,
         coalesce(ue.total_edits_made,0) as edits_made,
         coalesce(uv.upvotes_cast,0) as upvotes_cast,
         coalesce(uv.downvotes_cast,0) as downvotes_cast,
         coalesce(uv.bounties_started,0) as bounties_started,
         coalesce(uv.bounties_awarded,0) as bounties_awarded,
         coalesce(uv.total_bounty_amount,0) as total_bounty_amount,
         coalesce(uc.comment_count,0) as comment_count,
         coalesce(uc.avg_comment_len,0) as avg_comment_len,
         coalesce(qm.p90_q_views,0) as p90_q_views,
         coalesce(ut3.top3_tags, '(none)') as top3_tags,
         ur.activity_bucket,
         ur.days_since_seen,
         case
           when coalesce(ua.q_count,0) + coalesce(ua.a_count,0) = 0 then 0
           else round( (coalesce(am.accepted_answers,0) * 1.0 / greatest(coalesce(ua.a_count,0),1)) * 100, 2)
         end as accept_rate_pct,
         case
           when coalesce(ua.q_count,0) = 0 then null
           else round( (coalesce(qm.questions_with_accepted,0) * 1.0 / greatest(coalesce(ua.q_count,0),1)) * 100, 2)
         end as q_accept_presence_pct,
         case
           when coalesce(ua.a_count,0) = 0 then null
           else round(coalesce(am.avg_answer_score,0) * 1.0, 2)
         end as ans_avg_score_norm,
         coalesce(ar.agg_events,0) as agg_events,
         coalesce(ar.agg_score_like,0) as agg_score_like,
         ar.last_activity_any,
         ru.websiteurl,
         ua.total_views,
         ua.total_post_score,
         uc.comment_score,
         ub.distinct_badges,
         ub.tag_badges,
         qm.questions_total,
         am.answers_total
  from recent_users ru
  left join user_activity ua on ua.user_id = ru.user_id
  left join user_comments uc on uc.user_id = ru.user_id
  left join user_votes uv on uv.user_id = ru.user_id
  left join user_badges ub on ub.user_id = ru.user_id
  left join question_metrics qm on qm.user_id = ru.user_id
  left join answer_metrics am on am.user_id = ru.user_id
  left join user_duplicates ud on ud.user_id = ru.user_id
  left join user_edits ue on ue.user_id = ru.user_id
  left join user_top3_tags ut3 on ut3.user_id = ru.user_id
  left join activity_rank ar on ar.user_id = ru.user_id
  left join user_recency ur on ur.user_id = ru.user_id
),
ranked as (
  select fs.user_id,
         fs.displayname,
         fs.reputation,
         fs.norm_location,
         fs.q_count,
         fs.a_count,
         fs.accepted_answers,
         fs.q_with_accepted,
         fs.accept_rate_pct,
         fs.q_accept_presence_pct,
         fs.avg_q_views,
         fs.p90_q_views,
         fs.ans_avg_score_norm,
         fs.badges_total,
         fs.gold_badges,
         fs.silver_badges,
         fs.bronze_badges,
         fs.duplicate_links_count,
         fs.edits_made,
         fs.upvotes_cast,
         fs.downvotes_cast,
         fs.bounties_started,
         fs.bounties_awarded,
         fs.total_bounty_amount,
         fs.comment_count,
         fs.avg_comment_len,
         fs.top3_tags,
         fs.activity_bucket,
         fs.days_since_seen,
         fs.agg_events,
         fs.agg_score_like,
         fs.last_activity_any,
         fs.websiteurl,
         fs.total_views,
         fs.total_post_score,
         fs.comment_score,
         fs.distinct_badges,
         fs.tag_badges,
         fs.questions_total,
         fs.answers_total,
         row_number() over (order by
           case when fs.activity_bucket like 'Active-%' then 0 when fs.activity_bucket like 'Dormant-%' then 1 else 2 end,
           fs.gold_badges desc,
           fs.reputation desc,
           fs.agg_events desc,
           fs.accept_rate_pct desc nulls last,
           fs.agg_score_like desc
         ) as overall_rank,
         dense_rank() over (partition by fs.norm_location order by fs.reputation desc, fs.gold_badges desc, fs.agg_events desc) as location_rank
  from final_scores fs
),
thresholds as (
  select
    percentile_cont(0.5) within group (order by reputation) as p50_rep,
    percentile_cont(0.9) within group (order by reputation) as p90_rep,
    percentile_cont(0.5) within group (order by coalesce(agg_events,0)) as p50_events,
    percentile_cont(0.9) within group (order by coalesce(agg_events,0)) as p90_events
  from ranked
),
flagged as (
  select r.user_id,
         r.displayname,
         r.reputation,
         r.norm_location,
         r.q_count,
         r.a_count,
         r.accepted_answers,
         r.q_with_accepted,
         r.accept_rate_pct,
         r.q_accept_presence_pct,
         r.avg_q_views,
         r.p90_q_views,
         r.ans_avg_score_norm,
         r.badges_total,
         r.gold_badges,
         r.silver_badges,
         r.bronze_badges,
         r.duplicate_links_count,
         r.edits_made,
         r.upvotes_cast,
         r.downvotes_cast,
         r.bounties_started,
         r.bounties_awarded,
         r.total_bounty_amount,
         r.comment_count,
         r.avg_comment_len,
         r.top3_tags,
         r.activity_bucket,
         r.days_since_seen,
         r.agg_events,
         r.agg_score_like,
         r.last_activity_any,
         r.websiteurl,
         r.total_views,
         r.total_post_score,
         r.comment_score,
         r.distinct_badges,
         r.tag_badges,
         r.questions_total,
         r.answers_total,
         r.overall_rank,
         r.location_rank,
         case
           when r.reputation >= t.p90_rep and r.agg_events >= t.p90_events then 'Elite'
           when r.reputation >= t.p50_rep and r.agg_events >= t.p50_events then 'Power'
           when r.reputation is null then 'Unknown'
           else 'Regular'
         end as cohort
  from ranked r
  cross join thresholds t
)
select
  r.user_id,
  r.displayname,
  r.reputation,
  r.norm_location,
  r.q_count,
  r.a_count,
  r.accepted_answers,
  r.q_with_accepted,
  r.accept_rate_pct,
  r.q_accept_presence_pct,
  r.avg_q_views,
  r.p90_q_views,
  r.ans_avg_score_norm,
  r.badges_total,
  r.gold_badges,
  r.silver_badges,
  r.bronze_badges,
  r.duplicate_links_count,
  r.edits_made,
  r.upvotes_cast,
  r.downvotes_cast,
  r.bounties_started,
  r.bounties_awarded,
  r.total_bounty_amount,
  r.comment_count,
  r.avg_comment_len,
  r.top3_tags,
  r.activity_bucket,
  r.days_since_seen,
  r.agg_events,
  r.agg_score_like,
  r.last_activity_any,
  r.overall_rank,
  r.location_rank,
  f.cohort,
  coalesce(nullif(trim(r.websiteurl), ''), 'n/a') as websiteurl_normalized
from flagged f
join ranked r on r.user_id = f.user_id
where (r.reputation > 0 or r.badges_total > 0 or r.q_count > 0 or r.a_count > 0)
  and (r.downvotes_cast is null or r.downvotes_cast <= (r.upvotes_cast + 10))
  and (r.last_activity_any is null or r.last_activity_any <= cast('2024-10-01 12:34:56' as timestamp))
  and (r.norm_location not ilike '%outer space%' or r.gold_badges >= 1)
order by r.overall_rank
limit 500;