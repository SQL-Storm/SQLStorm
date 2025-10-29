-- {"query": "605.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3087} 
with recent_users as (
    select u.id as user_id,
           u.displayname,
           u.reputation,
           u.creationdate,
           u.location,
           coalesce(nullif(trim(u.websiteurl), ''), 'N/A') as websiteurl_norm,
           row_number() over (order by u.creationdate desc, u.id desc) as rn_desc_new
    from users u
    where u.creationdate >= (select max(creationdate) - interval '365 days' from users)
),
user_activity as (
    select u.id as user_id,
           count(distinct p.id) as post_cnt,
           sum(coalesce(p.score,0)) as post_score_sum,
           count(distinct c.id) as comment_cnt,
           sum(case when v.votetypeid = 2 then 1 when v.votetypeid = 3 then -1 else 0 end) as vote_balance,
           max(greatest(coalesce(p.lastactivitydate, p.creationdate), coalesce(c.creationdate, timestamp 'epoch'), coalesce(v.creationdate, timestamp 'epoch'))) as last_activity_at
    from users u
    left join posts p on p.owneruserid = u.id
    left join comments c on c.userid = u.id
    left join votes v on v.userid = u.id
    group by u.id
),
questions as (
    select p.*
    from posts p
    where p.posttypeid = 1
),
answers as (
    select p.*
    from posts p
    where p.posttypeid = 2
),
q_enriched as (
    select q.id as question_id,
           q.owneruserid as asker_id,
           q.creationdate as q_created,
           q.score as q_score,
           q.viewcount as q_views,
           q.answercount as q_answers,
           q.tags,
           q.title,
           q.acceptedanswerid,
           case when q.closuredate is not null or q.closeddate is not null then 1 else 0 end as is_closed
    from (
        select q.*,
               q.closeddate as closuredate
        from questions q
    ) q
),
a_enriched as (
    select a.id as answer_id,
           a.parentid as question_id,
           a.owneruserid as answerer_id,
           a.score as a_score,
           a.creationdate as a_created
    from answers a
),
tag_expanded as (
    select qe.question_id,
           lower(trim(tg)) as tag_name
    from q_enriched qe
    cross join lateral (
        select unnest(string_to_array(substring(qe.tags from 2 for length(qe.tags)-2), '><')) as tg
    ) s
),
tag_stats as (
    select te.tag_name,
           count(*) as tag_q_count,
           sum(coalesce(qe.q_views,0)) as tag_views,
           avg(qe.q_score) as tag_avg_q_score,
           percentile_cont(0.5) within group (order by qe.q_views) as tag_median_views
    from tag_expanded te
    join q_enriched qe on qe.question_id = te.question_id
    group by te.tag_name
    having count(*) > 10
),
dup_graph as (
    select pl.postid as dup_id,
           pl.relatedpostid as canonical_id,
           pl.creationdate as dup_linked_at
    from postlinks pl
    where pl.linktypeid = 3
),
dup_clusters as (
    select d.canonical_id,
           count(distinct d.dup_id) as dup_count,
           min(d.dup_linked_at) as first_dup_at,
           max(d.dup_linked_at) as last_dup_at
    from dup_graph d
    group by d.canonical_id
),
edits as (
    select ph.postid,
           count(*) filter (where ph.posthistorytypeid in (4,5,6,7,8,9,24)) as edit_events,
           min(ph.creationdate) filter (where ph.posthistorytypeid in (4,5,6)) as first_edit_at,
           max(ph.creationdate) filter (where ph.posthistorytypeid in (4,5,6)) as last_edit_at,
           count(*) filter (where ph.posthistorytypeid = 10) as close_events,
           count(*) filter (where ph.posthistorytypeid = 11) as reopen_events
    from posthistory ph
    group by ph.postid
),
accepted_map as (
    select qe.question_id,
           case when qe.acceptedanswerid is not null then 1 else 0 end as has_accepted
    from q_enriched qe
),
answerer_perf as (
    select ae.answerer_id,
           count(*) as answers_total,
           sum(case when ae.answer_id = qe.acceptedanswerid then 1 else 0 end) as answers_accepted,
           avg(ae.a_score) as avg_answer_score,
           percentile_disc(0.9) within group (order by ae.a_score) as p90_answer_score,
           min(ae.a_created) as first_answer_at,
           max(ae.a_created) as last_answer_at
    from a_enriched ae
    left join q_enriched qe on qe.question_id = ae.question_id
    group by ae.answerer_id
),
question_quality as (
    select qe.question_id,
           qe.asker_id,
           qe.q_score,
           qe.q_views,
           coalesce(ed.edit_events,0) as edit_events,
           coalesce(ed.close_events,0) as close_events,
           coalesce(ed.reopen_events,0) as reopen_events,
           coalesce(dc.dup_count,0) as dup_count,
           coalesce(am.has_accepted,0) as has_accepted,
           case when qe.q_views > 0 then qe.q_score::numeric / greatest(qe.q_views,1) else 0 end as score_per_view,
           case when qe.q_answers > 0 then qe.q_score::numeric / greatest(qe.q_answers,1) else qe.q_score end as score_per_answer
    from q_enriched qe
    left join edits ed on ed.postid = qe.question_id
    left join dup_clusters dc on dc.canonical_id = qe.question_id
    left join accepted_map am on am.question_id = qe.question_id
),
user_rollup as (
    select u.id as user_id,
           u.displayname,
           u.reputation,
           count(distinct q.question_id) as questions_asked,
           sum(q.q_score) as q_score_sum,
           avg(nullif(q.q_views,0)) as avg_q_views_nonzero,
           sum(case when q.has_accepted = 1 then 1 else 0 end) as questions_with_accept,
           sum(q.dup_count) as total_dups_to_their_qs,
           sum(q.edit_events) as total_q_edits,
           sum(q.close_events) as total_q_closes,
           sum(q.reopen_events) as total_q_reopens,
           max(q.q_views) as max_q_views,
           min(q.q_score) as worst_q_score,
           coalesce(up.post_cnt,0) as total_posts_by_user,
           coalesce(up.vote_balance,0) as vote_balance,
           up.last_activity_at
    from users u
    left join question_quality q on q.asker_id = u.id
    left join user_activity up on up.user_id = u.id
    group by u.id, u.displayname, u.reputation, up.post_cnt, up.vote_balance, up.last_activity_at
),
ranked_users as (
    select ur.*,
           dense_rank() over (order by coalesce(ur.q_score_sum,0) desc nulls last, coalesce(ur.questions_asked,0) desc, ur.reputation desc, ur.user_id) as rank_by_qimpact,
           ntile(10) over (order by coalesce(ur.avg_q_views_nonzero,0) desc nulls last) as decile_avg_views,
           row_number() over (partition by case when coalesce(ur.questions_asked,0) = 0 then 0 else 1 end order by coalesce(ur.q_score_sum,0) desc nulls last) as rn_participation
    from user_rollup ur
),
tag_engagement as (
    select te.tag_name,
           qe.asker_id as user_id,
           count(*) as tag_qs_by_user,
           avg(qe.q_score) as tag_avg_score_by_user
    from tag_expanded te
    join q_enriched qe on qe.question_id = te.question_id
    group by te.tag_name, qe.asker_id
),
user_top_tag as (
    select t.user_id,
           t.tag_name,
           t.tag_qs_by_user,
           t.tag_avg_score_by_user,
           row_number() over (partition by t.user_id order by t.tag_qs_by_user desc, t.tag_avg_score_by_user desc, t.tag_name) as rn
    from tag_engagement t
),
user_badges as (
    select b.userid as user_id,
           sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
           sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
           sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
           count(*) as total_badges,
           max(b.date) as last_badge_at
    from badges b
    group by b.userid
),
recent_activity_flags as (
    select ru.user_id,
           case when ru.last_activity_at >= now() - interval '30 days' then 1 else 0 end as active_30d,
           case when ru.last_activity_at >= now() - interval '90 days' then 1 else 0 end as active_90d
    from ranked_users ru
),
baseline as (
    select ru.user_id,
           ru.displayname,
           ru.reputation,
           ru.questions_asked,
           coalesce(ru.q_score_sum,0) as q_score_sum,
           coalesce(ru.avg_q_views_nonzero,0) as avg_q_views_nonzero,
           coalesce(ru.questions_with_accept,0) as questions_with_accept,
           coalesce(ru.total_dups_to_their_qs,0) as total_dups_to_their_qs,
           coalesce(ru.total_q_edits,0) as total_q_edits,
           coalesce(ru.total_q_closes,0) as total_q_closes,
           coalesce(ru.total_q_reopens,0) as total_q_reopens,
           coalesce(ru.max_q_views,0) as max_q_views,
           coalesce(ru.worst_q_score,0) as worst_q_score,
           ru.total_posts_by_user,
           ru.vote_balance,
           ru.last_activity_at,
           ru.rank_by_qimpact,
           ru.decile_avg_views,
           ru.rn_participation
    from ranked_users ru
),
filtered as (
    select b.*,
           coalesce(ub.total_badges,0) as total_badges,
           coalesce(ub.gold_badges,0) as gold_badges,
           coalesce(ub.silver_badges,0) as silver_badges,
           coalesce(ub.bronze_badges,0) as bronze_badges,
           ub.last_badge_at,
           r.active_30d,
           r.active_90d,
           utt.tag_name as top_tag,
           coalesce(utt.tag_qs_by_user,0) as top_tag_qs,
           coalesce(utt.tag_avg_score_by_user,0) as top_tag_avg_score
    from baseline b
    left join user_badges ub on ub.user_id = b.user_id
    left join recent_activity_flags r on r.user_id = b.user_id
    left join user_top_tag utt on utt.user_id = b.user_id and utt.rn = 1
    where (b.questions_asked > 0 or b.total_posts_by_user > 10)
)
select
    f.user_id,
    f.displayname,
    f.reputation,
    f.questions_asked,
    f.q_score_sum,
    f.avg_q_views_nonzero,
    f.questions_with_accept,
    f.total_dups_to_their_qs,
    f.total_q_edits,
    f.total_q_closes,
    f.total_q_reopens,
    f.max_q_views,
    f.worst_q_score,
    f.total_posts_by_user,
    f.vote_balance,
    f.rank_by_qimpact,
    f.decile_avg_views,
    f.rn_participation,
    f.total_badges,
    f.gold_badges,
    f.silver_badges,
    f.bronze_badges,
    f.last_badge_at,
    f.active_30d,
    f.active_90d,
    f.top_tag,
    f.top_tag_qs,
    f.top_tag_avg_score,
    case
        when f.questions_asked > 0 then round(100.0 * f.questions_with_accept / greatest(f.questions_asked,1), 2)
        else null
    end as accept_rate_pct,
    case
        when f.questions_asked > 0 then round(1.0 * f.q_score_sum / greatest(f.questions_asked,1), 3)
        else null
    end as avg_q_score,
    case
        when f.total_posts_by_user > 0 then round(1.0 * f.vote_balance / greatest(f.total_posts_by_user,1), 3)
        else null
    end as votes_per_post,
    coalesce(
        nullif(trim(split_part(coalesce((select websiteurl_norm from recent_users ru where ru.user_id = f.user_id), '')), '://', 2)), 
        'no-site'
    ) as website_hostish
from filtered f
where (
        f.active_90d = 1
        or f.rank_by_qimpact <= 1000
        or (f.gold_badges + f.silver_badges) >= 5
      )
and (
        f.top_tag is null
        or exists (
            select 1
            from tag_stats ts
            where ts.tag_name = f.top_tag
              and ts.tag_avg_q_score > 0
        )
    )
and (
        f.questions_asked = 0
        or f.avg_q_views_nonzero is null
        or f.avg_q_views_nonzero >= (
            select avg(tag_median_views)
            from tag_stats
        )
    )
order by f.rank_by_qimpact, f.user_id
limit 500;