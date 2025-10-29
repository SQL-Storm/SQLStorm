-- {"query": "772.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 4185} 
with recent_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.location,
        coalesce(nullif(trim(u.websiteurl), ''), 'N/A') as websiteurl,
        date_trunc('month', u.creationdate) as cohort_month,
        row_number() over (order by u.creationdate desc, u.id desc) as rn_newest
    from users u
    where u.reputation >= 1
),
user_activity as (
    select
        p.owneruserid as user_id,
        count(*) filter (where p.posttypeid = 1) as questions,
        count(*) filter (where p.posttypeid = 2) as answers,
        sum(coalesce(p.viewcount, 0)) as total_views,
        sum(coalesce(p.score, 0)) as post_score,
        avg(nullif(p.answercount, 0)) as avg_answers_per_q_with_answers,
        min(p.creationdate) as first_post_at,
        max(p.lastactivitydate) as last_activity_at
    from posts p
    where p.owneruserid is not null
    group by p.owneruserid
),
q_basics as (
    select
        p.id as question_id,
        p.owneruserid as asker_id,
        p.creationdate as asked_at,
        p.score as q_score,
        p.viewcount as q_views,
        p.answercount as q_answers,
        p.acceptedanswerid,
        p.tags,
        p.title
    from posts p
    where p.posttypeid = 1
),
a_basics as (
    select
        a.id as answer_id,
        a.parentid as question_id,
        a.owneruserid as answerer_id,
        a.creationdate as answered_at,
        a.score as a_score
    from posts a
    where a.posttypeid = 2
),
q_answer_stats as (
    select
        q.question_id,
        count(*) as answer_count,
        max(case when q.acceptedanswerid = a.answer_id then 1 else 0 end) as has_accepted,
        min(a.answered_at) as first_answer_time,
        max(a.a_score) as max_answer_score
    from q_basics q
    left join a_basics a on a.question_id = q.question_id
    group by q.question_id
),
q_time_to_first_answer as (
    select
        q.question_id,
        extract(epoch from (qa.first_answer_time - q.asked_at)) as secs_to_first_answer
    from q_basics q
    left join q_answer_stats qa on qa.question_id = q.question_id
),
q_votes as (
    select
        v.postid as post_id,
        sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
        sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
        sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites,
        sum(case when v.votetypeid in (8,9) then coalesce(v.bountyamount,0) else 0 end) as bounty_total
    from votes v
    group by v.postid
),
q_closed as (
    select
        ph.postid as question_id,
        min(ph.creationdate) as first_closed_at,
        max(ph.creationdate) as last_closed_at,
        count(*) filter (where ph.posthistorytypeid = 10) as close_events,
        count(*) filter (where ph.posthistorytypeid = 11) as reopen_events,
        max(try_cast(nullif(ph.comment,'') as int)) filter (where ph.posthistorytypeid = 10) as last_close_reason_id
    from posthistory ph
    where ph.posthistorytypeid in (10,11)
    group by ph.postid
),
dup_links as (
    select
        pl.postid as dup_post_id,
        pl.relatedpostid as original_post_id,
        min(pl.creationdate) as first_dup_link_at
    from postlinks pl
    where pl.linktypeid = 3
    group by pl.postid, pl.relatedpostid
),
tag_expanded as (
    select
        q.question_id,
        unnest(string_to_array(substring(q.tags, 2, greatest(length(q.tags)-2,0)), '><')) as tag
    from q_basics q
    where q.tags is not null and q.tags like '<%>'
),
tag_rank as (
    select
        t.tag,
        count(*) as tag_uses,
        row_number() over (order by count(*) desc, tag asc) as tag_rank_overall
    from tag_expanded t
    group by t.tag
),
user_badges as (
    select
        b.userid as user_id,
        count(*) as badges_total,
        count(*) filter (where b.class = 1) as gold,
        count(*) filter (where b.class = 2) as silver,
        count(*) filter (where b.class = 3) as bronze,
        max(b.date) as last_badge_at
    from badges b
    group by b.userid
),
-- Correlated aggregation: last comment per post and commenter diversity
post_comment_stats as (
    select
        c.postid,
        count(*) as comment_count,
        count(distinct c.userid) as distinct_commenters,
        max(c.creationdate) as last_comment_at,
        max(c.id) filter (where c.creationdate = (select max(c2.creationdate) from comments c2 where c2.postid = c.postid)) as last_comment_id
    from comments c
    group by c.postid
),
-- Windowed per-user question metrics
user_question_metrics as (
    select
        qb.asker_id as user_id,
        count(*) as questions_asked,
        avg(coalesce(qb.q_views,0)) as avg_q_views,
        avg(coalesce(qb.q_score,0)) as avg_q_score,
        percentile_cont(0.5) within group (order by coalesce(qtaf.secs_to_first_answer, 1e12)) as p50_time_to_first_answer_secs,
        sum(case when qa.has_accepted = 1 then 1 else 0 end) as accepted_questions,
        sum(coalesce(qv.favorites,0)) as total_favorites_on_questions
    from q_basics qb
    left join q_answer_stats qa on qa.question_id = qb.question_id
    left join q_time_to_first_answer qtaf on qtaf.question_id = qb.question_id
    left join q_votes qv on qv.post_id = qb.question_id
    group by qb.asker_id
),
-- Identify "hot" questions by combined windowed z-scores over views and score
question_hotness as (
    select
        q.question_id,
        q.asked_at,
        q.q_views,
        q.q_score,
        case when stddev_pop(coalesce(q.q_views,0)) over () > 0
             then (coalesce(q.q_views,0) - avg(coalesce(q.q_views,0)) over ()) / nullif(stddev_pop(coalesce(q.q_views,0)) over (),0)
             else 0 end
        +
        case when stddev_pop(coalesce(q.q_score,0)) over () > 0
             then (coalesce(q.q_score,0) - avg(coalesce(q.q_score,0)) over ()) / nullif(stddev_pop(coalesce(q.q_score,0)) over (),0)
             else 0 end
        as hot_z
    from q_basics q
),
-- Cohort-level user quality
cohort_user_quality as (
    select
        ru.cohort_month,
        percentile_cont(0.9) within group (order by ua.post_score) as p90_post_score,
        avg(ua.total_views) as avg_total_views,
        count(*) as users_in_cohort
    from recent_users ru
    left join user_activity ua on ua.user_id = ru.user_id
    group by ru.cohort_month
),
-- Build final per-user rollup with null-logic and string ops
user_rollup as (
    select
        ru.user_id,
        ru.displayname,
        ru.reputation,
        ru.cohort_month,
        ru.location,
        ru.websiteurl,
        ua.questions,
        ua.answers,
        ua.total_views,
        ua.post_score,
        ua.first_post_at,
        ua.last_activity_at,
        ub.badges_total,
        ub.gold,
        ub.silver,
        ub.bronze,
        ub.last_badge_at,
        uqm.questions_asked,
        uqm.avg_q_views,
        uqm.avg_q_score,
        uqm.p50_time_to_first_answer_secs,
        uqm.accepted_questions,
        uqm.total_favorites_on_questions,
        concat_ws(' | ',
            nullif(trim(ru.displayname), ''),
            case when ru.location ilike '%remote%' then 'REMOTE' else null end,
            case when coalesce(ub.gold,0) > 0 then 'GOLDER' else null end
        ) as flags
    from recent_users ru
    left join user_activity ua on ua.user_id = ru.user_id
    left join user_badges ub on ub.user_id = ru.user_id
    left join user_question_metrics uqm on uqm.user_id = ru.user_id
),
-- Heavy join: questions with various facets
question_facts as (
    select
        qb.question_id,
        qb.asker_id,
        qb.asked_at,
        qb.q_score,
        qb.q_views,
        qb.q_answers,
        qb.acceptedanswerid,
        qb.title,
        qb.tags,
        qa.answer_count,
        qa.has_accepted,
        qa.first_answer_time,
        qa.max_answer_score,
        qv.upvotes,
        qv.downvotes,
        qv.favorites,
        qv.bounty_total,
        qc.first_closed_at,
        qc.last_closed_at,
        qc.close_events,
        qc.reopen_events,
        qc.last_close_reason_id,
        pcs.comment_count,
        pcs.distinct_commenters,
        pcs.last_comment_at
    from q_basics qb
    left join q_answer_stats qa on qa.question_id = qb.question_id
    left join q_votes qv on qv.post_id = qb.question_id
    left join q_closed qc on qc.question_id = qb.question_id
    left join post_comment_stats pcs on pcs.postid = qb.question_id
),
-- Rank related duplicates and links
question_relations as (
    select
        qf.question_id,
        count(distinct dl.original_post_id) as duplicate_of_count,
        min(dl.first_dup_link_at) as first_dup_link_at
    from question_facts qf
    left join dup_links dl on dl.dup_post_id = qf.question_id
    group by qf.question_id
),
-- Final scoring per question
question_score as (
    select
        qf.question_id,
        qf.asker_id,
        qf.asked_at,
        qf.q_score,
        qf.q_views,
        qf.q_answers,
        qf.acceptedanswerid,
        qf.title,
        qf.tags,
        qr.duplicate_of_count,
        qr.first_dup_link_at,
        coalesce(qf.upvotes,0) - coalesce(qf.downvotes,0) as net_votes,
        coalesce(qf.favorites,0) as favorites,
        coalesce(qf.bounty_total,0) as bounty_total,
        coalesce(qf.comment_count,0) as comment_count,
        coalesce(qf.distinct_commenters,0) as distinct_commenters,
        qf.first_closed_at,
        qf.last_closed_at,
        qf.close_events,
        qf.reopen_events,
        case
            when qf.has_accepted = 1 then 1
            when qf.acceptedanswerid is not null then 1
            else 0
        end as has_accepted_anyway,
        extract(epoch from (qf.first_answer_time - qf.asked_at)) as secs_to_first_answer,
        case
            when qf.tags ilike '%<sql>%' then 2
            when qf.tags ilike '%<postgresql>%' then 3
            when qf.tags is null then 0
            else 1
        end as tag_weight_hint
    from question_facts qf
    left join question_relations qr on qr.question_id = qf.question_id
),
-- Window-based ranking and bucketing
question_ranked as (
    select
        qs.*,
        ntile(10) over (order by coalesce(qs.q_views,0) desc nulls last) as views_decile,
        row_number() over (partition by date_trunc('month', qs.asked_at) order by coalesce(qs.q_score, -2147483648) desc, qs.question_id) as monthly_rank_by_score,
        dense_rank() over (order by coalesce(qs.favorites,0) desc, coalesce(qs.net_votes,0) desc) as global_popularity_rank
    from question_score qs
),
-- Blend with tag ranks: most significant tag per question
question_top_tag as (
    select
        te.question_id,
        te.tag,
        tr.tag_rank_overall,
        row_number() over (partition by te.question_id order by tr.tag_rank_overall) as rn
    from tag_expanded te
    join tag_rank tr on tr.tag = te.tag
),
question_with_top_tag as (
    select
        qr.question_id,
        coalesce(qtt.tag, 'untagged') as top_tag,
        qtt.tag_rank_overall
    from question_ranked qr
    left join question_top_tag qtt on qtt.question_id = qr.question_id and qtt.rn = 1
),
-- Assemble final materialized-like set for benchmarking
final_agg as (
    select
        qr.question_id,
        qr.asker_id,
        ru.displayname as asker_name,
        coalesce(ru.reputation, 0) as asker_rep,
        ru.flags as user_flags,
        qr.asked_at,
        qr.q_score,
        qr.q_views,
        qr.q_answers,
        qr.net_votes,
        qr.favorites,
        qr.bounty_total,
        qr.comment_count,
        qr.distinct_commenters,
        qr.has_accepted_anyway,
        qr.secs_to_first_answer,
        qr.tag_weight_hint,
        qr.views_decile,
        qr.monthly_rank_by_score,
        qr.global_popularity_rank,
        qwt.top_tag,
        qwt.tag_rank_overall,
        case
            when qr.first_closed_at is not null and qr.reopen_events > 0 then 'closed_reopened'
            when qr.first_closed_at is not null then 'closed'
            else 'open'
        end as close_state,
        case
            when qr.duplicate_of_count > 0 then 'duplicate'
            else 'original'
        end as dup_state,
        left(coalesce(qr.title, ''), 150) as title_snippet
    from question_ranked qr
    left join user_rollup ru on ru.user_id = qr.asker_id
    left join question_with_top_tag qwt on qwt.question_id = qr.question_id
),
-- Create synthetic buckets using set operators on predicates
bucket_high_quality as (
    select question_id from final_agg
    where has_accepted_anyway = 1
      and coalesce(net_votes,0) >= 5
      and coalesce(favorites,0) >= 3
),
bucket_controversial as (
    select question_id from final_agg
    where coalesce(distinct_commenters,0) >= 5
       or (coalesce(upvotes,0) is null and coalesce(net_votes,0) between -2 and 2)
),
bucket_hot as (
    select q.question_id
    from question_hotness q
    where q.hot_z >= 2
),
combined_buckets as (
    select question_id, 'high_quality' as bucket from bucket_high_quality
    union all
    select question_id, 'controversial' from bucket_controversial
    union all
    select question_id, 'hot' from bucket_hot
),
bucket_rollup as (
    select
        fa.question_id,
        string_agg(cb.bucket, ',' order by cb.bucket) as bucket_tags
    from final_agg fa
    left join combined_buckets cb on cb.question_id = fa.question_id
    group by fa.question_id
),
-- Correlated subquery: compute recency adjusted score
final_scored as (
    select
        fa.*,
        br.bucket_tags,
        (
            coalesce(fa.net_votes,0) * 1.0
            + coalesce(fa.favorites,0) * 1.5
            + case when fa.has_accepted_anyway = 1 then 5 else 0 end
            + greatest(0, 10 - coalesce(fa.views_decile,10)) * 0.25
            + case when fa.close_state = 'open' then 1 else -2 end
            + case when fa.dup_state = 'duplicate' then -3 else 0 end
            + case when fa.top_tag ilike 'postgresql' then 2 when fa.top_tag ilike 'sql' then 1 else 0 end
            + least(5, coalesce((select count(*) from answers a where a.parentid = fa.question_id), 0)) * 0.5
        ) as composite_score,
        (
            extract(epoch from (now() - fa.asked_at)) / nullif(nullif(extract(epoch from (now() - fa.asked_at)),0),0)
        ) as recency_normalizer
    from final_agg fa
    left join bucket_rollup br on br.question_id = fa.question_id
)
select
    fs.question_id,
    fs.asker_id,
    fs.asker_name,
    fs.asker_rep,
    fs.user_flags,
    fs.asked_at,
    fs.top_tag,
    fs.tag_rank_overall,
    fs.close_state,
    fs.dup_state,
    coalesce(fs.bucket_tags, 'none') as bucket_tags,
    fs.views_decile,
    fs.monthly_rank_by_score,
    fs.global_popularity_rank,
    fs.q_views,
    fs.q_score,
    fs.net_votes,
    fs.favorites,
    fs.bounty_total,
    fs.comment_count,
    fs.distinct_commenters,
    fs.has_accepted_anyway,
    fs.secs_to_first_answer,
    round(fs.composite_score::numeric, 2) as composite_score,
    left(fs.title_snippet, 150) as title_snippet
from final_scored fs
where
    -- Complicated predicate mixing nulls, strings, and math
    (fs.top_tag is null or fs.top_tag not ilike any (array['meta','discussion']))
    and coalesce(fs.q_views,0) + coalesce(fs.favorites,0)*10 + coalesce(fs.net_votes,0)*20 >= 100
    and (fs.close_state <> 'closed' or coalesce(fs.reopen_events,0) > 0)
    and (fs.asker_rep > 100 or fs.has_accepted_anyway = 1 or fs.tag_rank_overall <= 1000)
    and (fs.secs_to_first_answer is null or fs.secs_to_first_answer >= 0)
order by
    fs.composite_score desc nulls last,
    fs.global_popularity_rank asc nulls last,
    fs.views_decile asc,
    fs.question_id
limit 500;