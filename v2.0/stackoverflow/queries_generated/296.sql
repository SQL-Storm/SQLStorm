-- {"query": "296.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3274} 
with recent_users as (
    select u.id as user_id,
           u.displayname,
           u.reputation,
           u.creationdate,
           coalesce(u.location, '[unknown]') as location,
           date_trunc('month', u.creationdate) as signup_month
    from users u
    where u.creationdate >= (select max(creationdate) - interval '3 years' from users)
),
activity as (
    select p.owneruserid as user_id,
           count(*) filter (where p.posttypeid = 1) as q_count,
           count(*) filter (where p.posttypeid = 2) as a_count,
           sum(greatest(p.score, 0)) as nonneg_score_sum,
           avg(nullif(p.viewcount, 0)) as avg_views_nonzero,
           count(*) filter (where p.closeddate is not null) as closed_count,
           count(distinct p.id) as all_posts
    from posts p
    where p.owneruserid is not null
      and p.creationdate >= (select max(creationdate) - interval '3 years' from posts)
    group by p.owneruserid
),
votes_agg as (
    select v.userid as user_id,
           count(*) filter (where v.votetypeid = 2) as upvotes_cast,
           count(*) filter (where v.votetypeid = 3) as downvotes_cast,
           count(*) filter (where v.votetypeid = 8) as bounties_started,
           sum(case when v.votetypeid in (8,9) then coalesce(v.bountyamount,0) else 0 end) as bounty_total
    from votes v
    where v.userid is not null
      and v.creationdate >= (select max(creationdate) - interval '3 years' from votes)
    group by v.userid
),
badges_agg as (
    select b.userid as user_id,
           count(*) filter (where b.class = 1) as gold,
           count(*) filter (where b.class = 2) as silver,
           count(*) filter (where b.class = 3) as bronze,
           count(*) filter (where b.tagbased = 1) as tag_badges,
           min(b.date) as first_badge_at,
           max(b.date) as last_badge_at
    from badges b
    group by b.userid
),
comments_agg as (
    select c.userid as user_id,
           count(*) as comments_count,
           avg(c.score) as avg_comment_score,
           max(c.creationdate) as last_comment_at
    from comments c
    where c.userid is not null
    group by c.userid
),
accepted_answers as (
    select a.owneruserid as user_id,
           count(*) as accepted_answers_count,
           avg(a.score) as avg_score_accepted
    from posts q
    join posts a on a.id = q.acceptedanswerid
    where q.posttypeid = 1
      and a.posttypeid = 2
      and a.owneruserid is not null
    group by a.owneruserid
),
dup_links as (
    select pl.postid as dup_post_id,
           pl.relatedpostid as original_post_id
    from postlinks pl
    where pl.linktypeid = 3
),
q_tag_counts as (
    select p.owneruserid as user_id,
           sum(coalesce(array_length(string_to_array(substring(p.tags, 2, length(p.tags)-2), '><'), 1), 0)) as total_tags_applied
    from posts p
    where p.posttypeid = 1
      and p.owneruserid is not null
    group by p.owneruserid
),
post_edits as (
    select ph.userid as user_id,
           count(*) filter (where ph.posthistorytypeid in (4,5,6)) as edits_made,
           count(*) filter (where ph.posthistorytypeid in (24)) as suggested_edits_applied,
           count(*) filter (where ph.posthistorytypeid in (10)) as close_votes_events
    from posthistory ph
    where ph.userid is not null
    group by ph.userid
),
post_quality as (
    select p.owneruserid as user_id,
           percentile_cont(0.5) within group (order by coalesce(p.score,0)) as median_post_score,
           percentile_cont(0.9) within group (order by coalesce(p.viewcount,0)) as p90_views,
           stddev_pop(coalesce(p.score,0)) as score_stddev
    from posts p
    where p.owneruserid is not null
    group by p.owneruserid
),
user_latest_activity as (
    select p.owneruserid as user_id,
           max(p.lastactivitydate) as last_post_activity_at,
           max(p.lasteditdate) as last_post_edit_at
    from posts p
    where p.owneruserid is not null
    group by p.owneruserid
),
question_outcomes as (
    select p.owneruserid as user_id,
           count(*) filter (where p.posttypeid = 1 and p.acceptedanswerid is not null) as questions_with_accepted,
           count(*) filter (where p.posttypeid = 1 and p.acceptedanswerid is null) as questions_without_accepted,
           count(*) filter (where p.posttypeid = 1 and p.closeddate is not null) as questions_closed
    from posts p
    where p.owneruserid is not null
    group by p.owneruserid
),
dup_outcomes as (
    select q.owneruserid as user_id,
           count(distinct d.dup_post_id) as questions_marked_duplicate,
           count(distinct d.original_post_id) as distinct_original_targets
    from dup_links d
    join posts q on q.id = d.postid and q.posttypeid = 1
    where q.owneruserid is not null
    group by q.owneruserid
),
w_rollup as (
    select u.user_id,
           u.displayname,
           u.reputation,
           u.location,
           u.signup_month,
           a.q_count,
           a.a_count,
           a.nonneg_score_sum,
           a.avg_views_nonzero,
           a.closed_count,
           a.all_posts,
           v.upvotes_cast,
           v.downvotes_cast,
           v.bounties_started,
           v.bounty_total,
           b.gold,
           b.silver,
           b.bronze,
           b.tag_badges,
           b.first_badge_at,
           b.last_badge_at,
           c.comments_count,
           c.avg_comment_score,
           c.last_comment_at,
           aa.accepted_answers_count,
           aa.avg_score_accepted,
           qt.total_tags_applied,
           pe.edits_made,
           pe.suggested_edits_applied,
           pe.close_votes_events,
           pq.median_post_score,
           pq.p90_views,
           pq.score_stddev,
           ula.last_post_activity_at,
           ula.last_post_edit_at,
           qo.questions_with_accepted,
           qo.questions_without_accepted,
           qo.questions_closed,
           do.questions_marked_duplicate,
           do.distinct_original_targets
    from recent_users u
    left join activity a on a.user_id = u.user_id
    left join votes_agg v on v.user_id = u.user_id
    left join badges_agg b on b.user_id = u.user_id
    left join comments_agg c on c.user_id = u.user_id
    left join accepted_answers aa on aa.user_id = u.user_id
    left join q_tag_counts qt on qt.user_id = u.user_id
    left join post_edits pe on pe.user_id = u.user_id
    left join post_quality pq on pq.user_id = u.user_id
    left join user_latest_activity ula on ula.user_id = u.user_id
    left join question_outcomes qo on qo.user_id = u.user_id
    left join dup_outcomes do on do.user_id = u.user_id
),
ranked as (
    select *,
           coalesce(a_count,0) + coalesce(q_count,0) as post_count,
           coalesce(upvotes_cast,0) - coalesce(downvotes_cast,0) as net_votes_cast,
           coalesce(gold,0)*5 + coalesce(silver,0)*3 + coalesce(bronze,0) as badge_points,
           case
             when coalesce(all_posts,0) = 0 then null
             else round(100.0 * coalesce(accepted_answers_count,0) / nullif(a_count,0), 2)
           end as accepted_rate_pct,
           case when location ilike '%remote%' or location ilike '%anywhere%' then 1 else 0 end as is_remoteish,
           dense_rank() over (order by coalesce(a_count,0) desc, coalesce(q_count,0) desc, coalesce(reputation,0) desc) as prod_rank,
           row_number() over (partition by signup_month order by coalesce(a_count,0) desc nulls last, coalesce(q_count,0) desc nulls last, reputation desc nulls last) as monthly_rank,
           sum(coalesce(nonneg_score_sum,0)) over (partition by signup_month) as month_score_sum,
           avg(coalesce(avg_views_nonzero,0)) over (partition by signup_month) as month_avg_views,
           lag(last_post_activity_at) over (partition by user_id order by last_post_activity_at) as prev_activity_same_user
    from w_rollup
),
anomalies as (
    select r.user_id,
           case
             when coalesce(r.post_count,0)=0 and (r.badge_points > 0 or r.comments_count > 0) then 'lurker-with-badges'
             when r.score_stddev is not null and r.score_stddev > 50 and coalesce(r.p90_views,0) < 100 then 'volatile-low-views'
             when r.accepted_rate_pct is not null and r.accepted_rate_pct > 95 and coalesce(r.a_count,0) >= 10 then 'super-answerer'
             when coalesce(r.questions_marked_duplicate,0) >= 5 then 'dupe-magnet'
             else null
           end as anomaly_flag
    from ranked r
),
normed as (
    select r.*,
           coalesce(r.post_count,0) as pc,
           coalesce(r.net_votes_cast,0) as nvc,
           coalesce(r.badge_points,0) as bp,
           coalesce(r.nonneg_score_sum,0) as nss,
           coalesce(r.median_post_score,0) as mps
    from ranked r
),
scored as (
    select n.*,
           round(
             0.30 * (case when pc=0 then 0 else ln(pc+1) end) +
             0.20 * (case when nvc=0 then 0 else nvc end) / nullif(pc,0) +
             0.25 * (case when nss=0 then 0 else ln(nss+1) end) +
             0.15 * (bp/10.0) +
             0.10 * (case when mps is null then 0 else mps end)
           , 4) as engagement_score
    from normed n
),
dupe_detail as (
    select q.owneruserid as user_id,
           count(*) as dup_pairs,
           count(distinct case when p2.posttypeid = 1 then p2.id end) as distinct_original_questions
    from postlinks pl
    join posts q on q.id = pl.postid and pl.linktypeid = 3
    left join posts p2 on p2.id = pl.relatedpostid
    where q.owneruserid is not null
    group by q.owneruserid
),
finalized as (
    select s.*,
           a.anomaly_flag,
           dd.dup_pairs,
           dd.distinct_original_questions,
           case
             when s.engagement_score is null then 'unknown'
             when s.engagement_score >= 5 then 'elite'
             when s.engagement_score >= 3 then 'high'
             when s.engagement_score >= 1 then 'medium'
             when s.engagement_score > 0 then 'low'
             else 'inactive'
           end as engagement_tier,
           case
             when s.displayname is null or trim(s.displayname) = '' then '[anon]'
             when position(' ' in s.displayname) > 0 then initcap(split_part(s.displayname, ' ', 1)) || ' ' ||
                  upper(left(split_part(s.displayname, ' ', 2), 1)) || '.'
             else initcap(s.displayname)
           end as normalized_displayname
    from scored s
    left join anomalies a on a.user_id = s.user_id
    left join dupe_detail dd on dd.user_id = s.user_id
)
select f.user_id,
       f.normalized_displayname,
       f.reputation,
       coalesce(f.location, '[unknown]') as location,
       f.signup_month,
       f.post_count,
       f.q_count,
       f.a_count,
       f.accepted_answers_count,
       f.accepted_rate_pct,
       f.questions_with_accepted,
       f.questions_without_accepted,
       f.questions_closed,
       coalesce(f.upvotes_cast,0) as upvotes_cast,
       coalesce(f.downvotes_cast,0) as downvotes_cast,
       f.net_votes_cast,
       f.badge_points,
       coalesce(f.gold,0) as gold,
       coalesce(f.silver,0) as silver,
       coalesce(f.bronze,0) as bronze,
       f.tag_badges,
       f.nonneg_score_sum,
       round(coalesce(f.avg_views_nonzero,0)::numeric,2) as avg_views_nonzero,
       f.median_post_score,
       f.p90_views,
       round(coalesce(f.score_stddev,0)::numeric,2) as score_stddev,
       f.total_tags_applied,
       f.edits_made,
       f.suggested_edits_applied,
       f.comments_count,
       round(coalesce(f.avg_comment_score,0)::numeric,2) as avg_comment_score,
       f.last_post_activity_at,
       f.last_post_edit_at,
       f.last_comment_at,
       f.questions_marked_duplicate,
       f.distinct_original_targets,
       f.dup_pairs,
       f.distinct_original_questions,
       f.prod_rank,
       f.monthly_rank,
       f.month_score_sum,
       f.month_avg_views,
       f.engagement_score,
       f.engagement_tier,
       f.anomaly_flag,
       case
         when f.closed_count > 0 or f.questions_closed > 0 then 'has-closures'
         when coalesce(f.questions_marked_duplicate,0) > 0 then 'has-duplicates'
         when f.accepted_answers_count is not null and f.accepted_answers_count > 0 then 'has-accepted'
         else 'none'
       end as moderation_signal,
       case when f.is_remoteish = 1 then 'remoteish' else 'n/a' end as location_hint
from finalized f
where (f.engagement_score is not null and f.engagement_score > 0)
   or (f.anomaly_flag is not null)
   or (f.prod_rank <= 100)
order by f.engagement_tier desc, f.engagement_score desc nulls last, f.prod_rank asc
limit 500;