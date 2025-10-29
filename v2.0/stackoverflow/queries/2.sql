-- {"query": "2.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2957}
with recent_users as (
    select u.id as user_id,
           u.displayname,
           u.reputation,
           u.creationdate,
           u.location,
           coalesce(nullif(trim(split_part(coalesce(u.websiteurl,''),'//',2)),''),'unknown') as site_host,
           date_trunc('month', u.creationdate) as cohort_month
    from users u
    where u.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '5 years'
),
question_posts as (
    select p.id,
           p.owneruserid as user_id,
           p.creationdate,
           p.score,
           p.viewcount,
           p.title,
           p.tags,
           p.answercount,
           p.closeddate
    from posts p
    where p.posttypeid = 1
      and p.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '5 years'
),
answer_posts as (
    select p.id,
           p.parentid as question_id,
           p.owneruserid as user_id,
           p.creationdate,
           p.score
    from posts p
    where p.posttypeid = 2
      and p.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '5 years'
),
votes_agg as (
    select v.postid,
           sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
           sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
           sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites,
           sum(case when v.votetypeid = 8 then coalesce(v.bountyamount,0) else 0 end) as bounty_started,
           sum(case when v.votetypeid = 9 then coalesce(v.bountyamount,0) else 0 end) as bounty_awarded,
           min(v.creationdate) filter (where v.votetypeid in (2,3,5)) as first_vote_at
    from votes v
    where v.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '5 years'
    group by v.postid
),
comments_agg as (
    select c.postid,
           count(*) as comment_count,
           max(c.score) as max_comment_score,
           max(c.creationdate) as last_comment_at
    from comments c
    where c.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '5 years'
    group by c.postid
),
post_links as (
    select pl.postid,
           sum(case when pl.linktypeid = 1 then 1 else 0 end) as linked_count,
           sum(case when pl.linktypeid = 3 then 1 else 0 end) as duplicate_count,
           bool_or(pl.linktypeid = 3) as has_duplicate_link
    from postlinks pl
    where pl.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '5 years'
    group by pl.postid
),
post_history_flags as (
    select ph.postid,
           bool_or(ph.posthistorytypeid in (10)) as was_closed,
           bool_or(ph.posthistorytypeid in (11)) as was_reopened,
           bool_or(ph.posthistorytypeid in (12)) as was_deleted,
           bool_or(ph.posthistorytypeid in (13)) as was_undeleted,
           bool_or(ph.posthistorytypeid in (19)) as was_protected,
           min(ph.creationdate) filter (where ph.posthistorytypeid in (10,11,12,13,19)) as first_moderation_at
    from posthistory ph
    where ph.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '5 years'
    group by ph.postid
),
tags_expanded as (
    select q.id as post_id,
           unnest(string_to_array(nullif(substring(q.tags, 2, greatest(length(q.tags)-2,0)),''), '><')) as tag
    from question_posts q
    where q.tags is not null
),
tag_stats as (
    select te.post_id,
           count(*) as tag_count,
           sum(case when lower(te.tag) in ('sql','postgresql','mysql','tsql','sqlite') then 1 else 0 end) as db_tag_hits,
           max(case when lower(te.tag) like '%sql%' then 1 else 0 end) as has_sqlish
    from tags_expanded te
    group by te.post_id
),
answers_per_question as (
    select a.question_id,
           count(*) as answers_total,
           sum(case when a.score > 0 then 1 else 0 end) as answers_positive,
           max(a.creationdate) as last_answer_at
    from answer_posts a
    group by a.question_id
),
question_enriched as (
    select q.id,
           q.user_id as owneruserid,
           q.creationdate,
           q.score,
           q.viewcount,
           q.title,
           q.tags,
           q.answercount,
           q.closeddate,
           coalesce(v.upvotes,0) as upvotes,
           coalesce(v.downvotes,0) as downvotes,
           coalesce(v.favorites,0) as favorites,
           coalesce(v.bounty_started,0) as bounty_started,
           coalesce(v.bounty_awarded,0) as bounty_awarded,
           v.first_vote_at,
           coalesce(c.comment_count,0) as comment_count,
           c.max_comment_score,
           c.last_comment_at,
           coalesce(l.linked_count,0) as linked_count,
           coalesce(l.duplicate_count,0) as duplicate_count,
           coalesce(l.has_duplicate_link,false) as has_duplicate_link,
           ph.was_closed,
           ph.was_reopened,
           ph.was_deleted,
           ph.was_undeleted,
           ph.was_protected,
           ph.first_moderation_at,
           ts.tag_count,
           ts.db_tag_hits,
           ts.has_sqlish
    from question_posts q
    left join votes_agg v on v.postid = q.id
    left join comments_agg c on c.postid = q.id
    left join post_links l on l.postid = q.id
    left join post_history_flags ph on ph.postid = q.id
    left join tag_stats ts on ts.post_id = q.id
),
user_badge_rollup as (
    select b.userid,
           count(*) as badges_total,
           sum(case when b.class = 1 then 1 else 0 end) as gold,
           sum(case when b.class = 2 then 1 else 0 end) as silver,
           sum(case when b.class = 3 then 1 else 0 end) as bronze,
           sum(case when coalesce(b.tagbased, false) = true then 1 else 0 end) as tag_badges
    from badges b
    where b.date >= cast('2024-10-01 12:34:56' as timestamp) - interval '5 years'
    group by b.userid
),
question_with_users as (
    select qe.*,
           ru.user_id,
           ru.displayname,
           ru.reputation,
           ru.location,
           ru.cohort_month,
           ubr.badges_total,
           ubr.gold,
           ubr.silver,
           ubr.bronze,
           ubr.tag_badges
    from question_enriched qe
    left join recent_users ru on ru.user_id = qe.owneruserid
    left join user_badge_rollup ubr on ubr.userid = ru.user_id
),
scored as (
    select qwu.*,
           case
             when qwu.answercount is null then null
             when qwu.answercount = 0 then 0
             else qwu.answercount
           end as answercount_sanitized,
           (coalesce(qwu.upvotes,0) - 0.5 * coalesce(qwu.downvotes,0)) as net_votes,
           (coalesce(qwu.score,0) + coalesce(qwu.upvotes,0) - coalesce(qwu.downvotes,0)) as blended_score,
           coalesce(qwu.viewcount,0) / nullif(extract(epoch from (cast('2024-10-01 12:34:56' as timestamp) - qwu.creationdate))/86400.0,0) as views_per_day,
           case when qwu.closeddate is not null then 1 else 0 end as is_closed_int,
           case when coalesce(qwu.was_reopened, false) = true then 1 else 0 end as was_reopened_int,
           coalesce(qwu.db_tag_hits,0) + coalesce(qwu.has_sqlish,0) as db_signal
    from question_with_users qwu
),
-- compute p90 blended per all rows using a scalar subquery to avoid ordered-set OVER
p90_calc as (
    select percentile_disc(0.9) within group (order by blended_score) as p90_blended
    from scored
),
ranked as (
    select s.*,
           row_number() over (partition by date_trunc('month', s.creationdate) order by s.blended_score desc nulls last, s.viewcount desc nulls last) as rn_month_top,
           rank() over (order by s.net_votes desc nulls last) as rk_global_net,
           dense_rank() over (partition by coalesce(s.location,'unknown') order by s.views_per_day desc nulls last) as dr_by_location,
           p.p90_blended
    from scored s
    cross join p90_calc p
),
dup_clusters as (
    select q.id as post_id,
           count(*) filter (where pl.linktypeid = 3) as dup_links_out,
           count(distinct case when pl.linktypeid = 3 then pl.relatedpostid end) as dup_targets
    from posts q
    left join postlinks pl on pl.postid = q.id
    where q.posttypeid = 1
      and q.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '5 years'
    group by q.id
),
final_base as (
    select r.*,
           dc.dup_links_out,
           dc.dup_targets,
           case when coalesce(r.has_duplicate_link,false) or coalesce(dc.dup_links_out,0) > 0 then 1 else 0 end as is_marked_duplicate
    from ranked r
    left join dup_clusters dc on dc.post_id = r.id
),
cohort_summaries as (
    select fb.cohort_month,
           count(*) as q_count,
           avg(fb.blended_score) as avg_blended,
           stddev_pop(fb.blended_score) as sd_blended,
           sum(case when coalesce(fb.is_marked_duplicate,0) = 1 then 1 else 0 end) as dup_count,
           sum(case when coalesce(fb.was_protected, false) = true then 1 else 0 end) as protected_count
    from final_base fb
    group by fb.cohort_month
),
heavy_users as (
    select ru.user_id,
           count(*) as q_count,
           sum(coalesce(qe.viewcount,0)) as total_views,
           avg(coalesce(qe.score,0)) as avg_score
    from recent_users ru
    join question_enriched qe on qe.owneruserid = ru.user_id
    group by ru.user_id
    having count(*) >= 10
),
top_tags as (
    select te.tag,
           count(*) as tag_qs,
           sum(coalesce(qe.score,0)) as tag_score
    from tags_expanded te
    join question_enriched qe on qe.id = te.post_id
    group by te.tag
    having count(*) > 50
),
user_activity_flag as (
    select ru.user_id,
           exists (
             select 1
             from comments c
             where c.userid = ru.user_id
               and c.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '1 year'
             limit 1
           ) as active_commenter
    from recent_users ru
)
select
    fb.id as question_id,
    coalesce(fb.title, concat('[untitled-', cast(fb.id as text), ']')) as title_or_placeholder,
    fb.creationdate,
    fb.displayname as owner_displayname,
    coalesce(fb.location,'unknown') as owner_location,
    fb.reputation,
    fb.badges_total,
    (coalesce(fb.gold,0) || '/' || coalesce(fb.silver,0) || '/' || coalesce(fb.bronze,0)) as badge_mix,
    fb.viewcount,
    fb.answercount_sanitized as answers,
    fb.upvotes,
    fb.downvotes,
    fb.net_votes,
    fb.favorites,
    fb.blended_score,
    round(cast(fb.views_per_day as numeric), 2) as views_per_day,
    fb.tag_count,
    fb.db_signal,
    fb.linked_count,
    fb.duplicate_count,
    coalesce(fb.is_marked_duplicate,0) as is_marked_duplicate,
    coalesce(fb.was_closed, false) as was_closed,
    coalesce(fb.was_reopened, false) as was_reopened,
    coalesce(fb.was_deleted, false) as was_deleted,
    coalesce(fb.was_undeleted, false) as was_undeleted,
    coalesce(fb.was_protected, false) as was_protected,
    coalesce(fb.first_vote_at, fb.creationdate) as first_engagement_at,
    fb.last_comment_at,
    fb.rn_month_top,
    fb.rk_global_net,
    fb.dr_by_location,
    cs.q_count as cohort_q_count,
    cs.avg_blended as cohort_avg_blended,
    ht.q_count as heavy_user_qs,
    tt.tag_qs as top_tag_qs,
    ua.active_commenter,
    case
      when fb.blended_score >= fb.p90_blended then 'P90+'
      when fb.blended_score is null then 'Unknown'
      else 'Sub-P90'
    end as blended_bucket
from final_base fb
left join cohort_summaries cs on cs.cohort_month = fb.cohort_month
left join heavy_users ht on ht.user_id = fb.user_id
left join user_activity_flag ua on ua.user_id = fb.user_id
left join lateral (
    select te.tag, tt.tag_qs, tt.tag_score
    from tags_expanded te
    left join top_tags tt on tt.tag = te.tag
    where te.post_id = fb.id
    order by coalesce(tt.tag_score, 0) desc, te.tag
    limit 1
) tt on true
where (
        coalesce(fb.dr_by_location, 999999) <= 5
        or coalesce(fb.rn_month_top, 999999) <= 10
        or (coalesce(fb.is_marked_duplicate,0) = 1 and coalesce(fb.net_votes,0) >= 0)
      )
  and coalesce(fb.viewcount,0) > 0
  and (
        coalesce(fb.db_signal,0) > 0
        or (fb.tag_count is null and coalesce(fb.score,0) >= 0)
      )
order by
    fb.rn_month_top nulls last,
    fb.blended_score desc nulls last,
    fb.views_per_day desc nulls last
limit 500;