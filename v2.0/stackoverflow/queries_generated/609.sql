-- {"query": "609.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3372} 
with recent_users as (
    select u.id as user_id,
           u.displayname,
           u.location,
           u.reputation,
           u.creationdate,
           coalesce(nullif(trim(u.websiteurl), ''), 'n/a') as websiteurl,
           row_number() over (order by u.creationdate desc, u.id) as rn
    from users u
    where u.creationdate >= (select max(creationdate) - interval '365 days' from users)
),
badge_rollup as (
    select b.userid,
           count(*) as total_badges,
           sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
           sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
           sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
           min(b.date) as first_badge_date,
           max(b.date) as last_badge_date,
           count(*) filter (where b.tagbased = true) as tag_badges
    from badges b
    group by b.userid
),
question_activity as (
    select p.owneruserid as user_id,
           count(*) as q_count,
           sum(coalesce(p.viewcount, 0)) as q_views,
           sum(coalesce(p.score, 0)) as q_score,
           avg(nullif(p.answercount, 0)) as avg_answers_per_q,
           max(p.creationdate) as last_q_date
    from posts p
    where p.posttypeid = 1
    group by p.owneruserid
),
answer_activity as (
    select p.owneruserid as user_id,
           count(*) as a_count,
           sum(coalesce(p.score, 0)) as a_score,
           max(p.creationdate) as last_a_date,
           count(*) filter (
               where exists (
                   select 1
                   from posts q
                   where q.id = p.parentid
                     and q.acceptedanswerid = p.id
               )
           ) as accepted_answers
    from posts p
    where p.posttypeid = 2
    group by p.owneruserid
),
comment_stats as (
    select c.userid as user_id,
           count(*) as c_count,
           sum(coalesce(c.score, 0)) as c_score,
           max(c.creationdate) as last_c_date
    from comments c
    group by c.userid
),
post_edit_events as (
    select ph.userid as user_id,
           count(*) filter (where ph.posthistorytypeid in (4,5,6,7,8,9,24)) as edit_events,
           count(*) filter (where ph.posthistorytypeid in (10,11,12,13,14,15,19,20,35)) as mod_state_events,
           max(ph.creationdate) as last_ph_date
    from posthistory ph
    group by ph.userid
),
dup_links as (
    select pl.postid,
           pl.relatedpostid,
           pl.creationdate,
           row_number() over (partition by pl.postid order by pl.creationdate desc, pl.id desc) as rn
    from postlinks pl
    where pl.linktypeid = 3
),
tag_explode as (
    select p.id as post_id,
           lower(trim(tg)) as tag
    from posts p
    cross join lateral unnest(
        case
            when p.tags is null then array[]::varchar[]
            when length(p.tags) <= 2 then array[]::varchar[]
            else string_to_array(substring(p.tags, 2, length(p.tags)-2), '><')
        end
    ) as tg
    where p.posttypeid = 1
),
user_top_tag as (
    select p.owneruserid as user_id,
           t.tag,
           count(*) as tag_q_count,
           row_number() over (partition by p.owneruserid order by count(*) desc, min(p.creationdate)) as rn
    from posts p
    join tag_explode t on t.post_id = p.id
    where p.posttypeid = 1
    group by p.owneruserid, t.tag
),
user_quality_score as (
    select u.id as user_id,
           -- Combine various metrics into a single normalized score with null-safe arithmetic
           (
             0.35 * coalesce(qa.q_score::numeric / nullif(qa.q_count,0), 0) +
             0.40 * coalesce(aa.a_score::numeric / nullif(aa.a_count,0), 0) +
             0.10 * least(coalesce(br.gold_badges,0), 10) +
             0.05 * least(coalesce(br.silver_badges,0) / 2.0, 10) +
             0.05 * least(coalesce(br.bronze_badges,0) / 3.0, 10) +
             0.05 * coalesce(cs.c_score::numeric / nullif(cs.c_count,0), 0)
           ) as quality_score
    from users u
    left join question_activity qa on qa.user_id = u.id
    left join answer_activity aa on aa.user_id = u.id
    left join badge_rollup br on br.userid = u.id
    left join comment_stats cs on cs.user_id = u.id
),
recent_dupe_pairs as (
    select q.owneruserid as user_id,
           q.id as question_id,
           q.title as question_title,
           d.relatedpostid as original_id,
           d.creationdate as dupe_mark_date
    from posts q
    join dup_links d on d.postid = q.id and d.rn = 1
    where q.posttypeid = 1
),
user_recency as (
    select u.id as user_id,
           greatest(
             coalesce(qa.last_q_date, 'epoch'::timestamp),
             coalesce(aa.last_a_date, 'epoch'::timestamp),
             coalesce(cs.last_c_date, 'epoch'::timestamp),
             coalesce(pe.last_ph_date, 'epoch'::timestamp),
             coalesce(u.lastaccessdate, 'epoch'::timestamp)
           ) as last_seen
    from users u
    left join question_activity qa on qa.user_id = u.id
    left join answer_activity aa on aa.user_id = u.id
    left join comment_stats cs on cs.user_id = u.id
    left join post_edit_events pe on pe.user_id = u.id
),
user_favorite_ratio as (
    select p.owneruserid as user_id,
           sum(coalesce(p.favoritecount,0)) as favs,
           count(*) filter (where p.posttypeid = 1) as q_posts,
           coalesce(sum(p.favoritecount)::numeric / nullif(count(*) filter (where p.posttypeid = 1),0), 0) as fav_per_q
    from posts p
    where p.owneruserid is not null
    group by p.owneruserid
),
user_median_post_score as (
    select owneruserid as user_id,
           percentile_cont(0.5) within group (order by coalesce(score,0)) as median_post_score
    from posts
    where owneruserid is not null
    group by owneruserid
),
user_ranked as (
    select ru.user_id,
           ru.displayname,
           ru.location,
           ru.reputation,
           ru.creationdate,
           ru.websiteurl,
           br.total_badges,
           br.gold_badges,
           br.silver_badges,
           br.bronze_badges,
           br.tag_badges,
           qa.q_count,
           qa.q_views,
           qa.q_score,
           qa.avg_answers_per_q,
           aa.a_count,
           aa.a_score,
           aa.accepted_answers,
           cs.c_count,
           cs.c_score,
           pe.edit_events,
           pe.mod_state_events,
           ur.last_seen,
           ut.tag as top_tag,
           uqs.quality_score,
           ufr.fav_per_q,
           umps.median_post_score,
           row_number() over (
               order by
                 coalesce(uqs.quality_score, -1e9) desc,
                 coalesce(aa.accepted_answers, 0) desc,
                 coalesce(qa.q_views, 0) desc,
                 ru.reputation desc,
                 ru.user_id
           ) as overall_rank
    from recent_users ru
    left join badge_rollup br on br.userid = ru.user_id
    left join question_activity qa on qa.user_id = ru.user_id
    left join answer_activity aa on aa.user_id = ru.user_id
    left join comment_stats cs on cs.user_id = ru.user_id
    left join post_edit_events pe on pe.user_id = ru.user_id
    left join user_recency ur on ur.user_id = ru.user_id
    left join user_top_tag ut on ut.user_id = ru.user_id and ut.rn = 1
    left join user_quality_score uqs on uqs.user_id = ru.user_id
    left join user_favorite_ratio ufr on ufr.user_id = ru.user_id
    left join user_median_post_score umps on umps.user_id = ru.user_id
),
question_enrichment as (
    select q.id as question_id,
           q.owneruserid as user_id,
           q.creationdate as q_created,
           q.score as q_score,
           q.viewcount as q_views,
           q.answercount as q_answers,
           q.title as q_title,
           q.tags as q_tags,
           coalesce((
               select sum(case when v.votetypeid = 2 then 1 when v.votetypeid = 3 then -1 else 0 end)
               from votes v
               where v.postid = q.id
           ), 0) as net_votes,
           case when exists (
               select 1 from posts a where a.id = q.acceptedanswerid
           ) then 1 else 0 end as has_accepted_answer,
           (select count(*) from comments c where c.postid = q.id) as comment_count,
           (select min(p2.creationdate) from posts p2 where p2.parentid = q.id and p2.posttypeid = 2) as first_answer_date,
           (select array_agg(distinct lower(tag)) from tag_explode te where te.post_id = q.id) as tag_array
    from posts q
    where q.posttypeid = 1
),
ranked_questions as (
    select qe.*,
           -- compute a composite difficulty/attention score
           (
             0.5 * coalesce(qe.q_views, 0)::numeric +
             3.0 * coalesce(qe.q_answers, 0)::numeric +
             10.0 * coalesce(qe.has_accepted_answer, 0)::numeric +
             2.0 * coalesce(qe.net_votes, 0)::numeric -
             0.2 * coalesce(qe.q_score, 0)::numeric
           ) as attention_score,
           dense_rank() over (order by coalesce(qe.q_views,0) desc) as dr_by_views,
           dense_rank() over (order by coalesce(qe.q_score,0) desc) as dr_by_score
    from question_enrichment qe
),
user_question_rollup as (
    select rq.user_id,
           count(*) as rq_count,
           avg(attention_score) as avg_attention,
           max(attention_score) as max_attention,
           min(attention_score) as min_attention,
           percentile_cont(0.9) within group (order by attention_score) as p90_attention
    from ranked_questions rq
    group by rq.user_id
),
final_users as (
    select ur.*,
           coalesce(uqr.rq_count, 0) as rq_count,
           uqr.avg_attention,
           uqr.max_attention,
           uqr.min_attention,
           uqr.p90_attention
    from user_ranked ur
    left join user_question_rollup uqr on uqr.user_id = ur.user_id
),
dupe_pair_details as (
    select rdp.user_id,
           count(*) as duped_q_count,
           count(distinct rdp.original_id) as unique_originals,
           min(rdp.dupe_mark_date) as first_dupe_mark,
           max(rdp.dupe_mark_date) as last_dupe_mark
    from recent_dupe_pairs rdp
    group by rdp.user_id
),
activity_trend as (
    select p.owneruserid as user_id,
           date_trunc('month', p.creationdate) as month,
           count(*) filter (where p.posttypeid = 1) as q_monthly,
           count(*) filter (where p.posttypeid = 2) as a_monthly,
           count(*) filter (where p.posttypeid not in (1,2)) as other_monthly
    from posts p
    where p.owneruserid is not null
      and p.creationdate >= (select max(creationdate) - interval '365 days' from posts)
    group by p.owneruserid, date_trunc('month', p.creationdate)
),
activity_trend_agg as (
    select user_id,
           sum(q_monthly) as q_yr,
           sum(a_monthly) as a_yr,
           sum(other_monthly) as other_yr,
           stddev_pop(q_monthly::numeric) as q_stdev,
           stddev_pop(a_monthly::numeric) as a_stdev
    from activity_trend
    group by user_id
)
select
    fu.overall_rank,
    fu.user_id,
    fu.displayname,
    coalesce(nullif(fu.location, ''), 'unknown') as location,
    fu.reputation,
    fu.creationdate,
    fu.websiteurl,
    fu.total_badges,
    fu.gold_badges,
    fu.silver_badges,
    fu.bronze_badges,
    fu.tag_badges,
    fu.q_count,
    fu.q_views,
    fu.q_score,
    fu.avg_answers_per_q,
    fu.a_count,
    fu.a_score,
    fu.accepted_answers,
    fu.c_count,
    fu.c_score,
    fu.edit_events,
    fu.mod_state_events,
    fu.last_seen,
    fu.top_tag,
    fu.quality_score,
    fu.fav_per_q,
    fu.median_post_score,
    fu.rq_count,
    fu.avg_attention,
    fu.max_attention,
    fu.min_attention,
    fu.p90_attention,
    coalesce(dpd.duped_q_count, 0) as duped_q_count,
    coalesce(dpd.unique_originals, 0) as unique_originals,
    dpd.first_dupe_mark,
    dpd.last_dupe_mark,
    ata.q_yr,
    ata.a_yr,
    ata.other_yr,
    ata.q_stdev,
    ata.a_stdev,
    case
      when fu.quality_score is null then 'unrated'
      when fu.quality_score >= 50 then 'elite'
      when fu.quality_score >= 20 then 'pro'
      when fu.quality_score >= 5 then 'journeyman'
      when fu.quality_score > 0 then 'novice'
      else 'needs-improvement'
    end as quality_bucket
from final_users fu
left join dupe_pair_details dpd on dpd.user_id = fu.user_id
left join activity_trend_agg ata on ata.user_id = fu.user_id
where (
    fu.quality_score is not null
    or coalesce(fu.a_count, 0) + coalesce(fu.q_count, 0) + coalesce(fu.c_count, 0) > 0
)
and (
    fu.last_seen >= (select max(lastaccessdate) - interval '365 days' from users)
    or fu.reputation >= (select percentile_cont(0.95) within group (order by reputation) from users)
)
order by fu.overall_rank
limit 250;