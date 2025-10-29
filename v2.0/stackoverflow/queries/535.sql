-- {"query": "535.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2704}
with recent_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.location,
        date_trunc('month', u.creationdate) as cohort_month,
        count(*) over (partition by date_trunc('month', u.creationdate)) as cohort_size
    from users u
    where u.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '5 years'
),
questions as (
    select
        p.id,
        p.owneruserid as user_id,
        p.creationdate,
        p.score,
        p.viewcount,
        p.favoritecount,
        p.commentcount,
        p.title,
        p.tags,
        p.acceptedanswerid,
        p.closeddate,
        p.communityowneddate
    from posts p
    where p.posttypeid = 1
      and p.creationdate >= (select min(creationdate) from recent_users)
),
answers as (
    select
        p.id,
        p.parentid as question_id,
        p.owneruserid as user_id,
        p.creationdate,
        p.score
    from posts p
    where p.posttypeid = 2
),
activity_window as (
    select
        q.id as question_id,
        q.user_id as asker_id,
        q.creationdate as question_created,
        q.score as question_score,
        q.viewcount,
        q.favoritecount,
        q.commentcount,
        q.title,
        q.tags,
        q.acceptedanswerid,
        q.closeddate,
        q.communityowneddate,
        coalesce(a.count_answers_7d, 0) as answers_7d,
        coalesce(a.count_answers_30d, 0) as answers_30d,
        coalesce(a.max_answer_score_30d, 0) as max_answer_score_30d,
        coalesce(aa.fastest_answer_minutes, null) as fastest_answer_minutes
    from questions q
    left join lateral (
        select
            count(*) filter (where an.creationdate <= q.creationdate + interval '7 days') as count_answers_7d,
            count(*) filter (where an.creationdate <= q.creationdate + interval '30 days') as count_answers_30d,
            max(an.score) filter (where an.creationdate <= q.creationdate + interval '30 days') as max_answer_score_30d
        from answers an
        where an.question_id = q.id
    ) a on true
    left join lateral (
        select extract(epoch from min(an.creationdate) - q.creationdate)/60.0 as fastest_answer_minutes
        from answers an
        where an.question_id = q.id
          and an.creationdate >= q.creationdate
    ) aa on true
),
question_meta as (
    select
        aw.*,
        case when aw.acceptedanswerid is not null then 1 else 0 end as has_accepted,
        case when aw.closeddate is not null then 1 else 0 end as is_closed,
        case when aw.communityowneddate is not null then 1 else 0 end as is_community
    from activity_window aw
),
tag_explode as (
    select
        qm.question_id,
        lower(trim(tg)) as tag
    from question_meta qm
    cross join lateral unnest(string_to_array(substring(coalesce(qm.tags,''), 2, greatest(length(coalesce(qm.tags,'')) - 2, 0)), '><')) as tg
),
tag_stats as (
    select
        te.tag,
        count(*) as tag_question_count,
        avg(qm.question_score) as avg_question_score,
        percentile_cont(0.5) within group (order by qm.viewcount) as p50_views,
        max(qm.answers_30d) as max_answers_30d
    from tag_explode te
    join question_meta qm on qm.question_id = te.question_id
    group by te.tag
    having count(*) > 50
),
user_activity as (
    select
        ru.user_id,
        ru.displayname,
        ru.reputation,
        ru.cohort_month,
        count(distinct q.id) as questions_asked,
        sum(case when qm.has_accepted = 1 then 1 else 0 end) as questions_with_accept,
        avg(nullif(qm.fastest_answer_minutes, 0)) as avg_fastest_answer_min,
        sum(qm.answers_7d) as answers_within_7d_total,
        sum(qm.answers_30d) as answers_within_30d_total,
        avg(qm.question_score) as avg_question_score,
        avg(qm.viewcount) as avg_views
    from recent_users ru
    left join posts q on q.posttypeid = 1 and q.owneruserid = ru.user_id
    left join question_meta qm on qm.question_id = q.id
    group by ru.user_id, ru.displayname, ru.reputation, ru.cohort_month
),
vote_agg as (
    select
        v.postid,
        sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
        sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
        sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites,
        sum(case when v.votetypeid in (8,9) then coalesce(v.bountyamount,0) else 0 end) as bounty_total
    from votes v
    group by v.postid
),
comment_sentiment as (
    select
        c.postid,
        avg(case
            when lower(c.text) like '%thank%' or lower(c.text) like '%great%' or lower(c.text) like '%help%' or lower(c.text) like '%nice%' or lower(c.text) like '%awesome%' then 1
            when lower(c.text) like '%bad%' or lower(c.text) like '%terrible%' or lower(c.text) like '%useless%' or lower(c.text) like '%wrong%' or lower(c.text) like '%hate%' then -1
            else 0 end
        ) as avg_sentiment,
        count(*) as comment_count
    from comments c
    group by c.postid
),
post_enriched as (
    select
        qm.question_id,
        qm.asker_id,
        qm.question_created,
        qm.title,
        qm.tags,
        qm.question_score,
        qm.viewcount,
        coalesce(va.upvotes,0) as upvotes,
        coalesce(va.downvotes,0) as downvotes,
        coalesce(va.favorites,0) as favorites_votes,
        coalesce(va.bounty_total,0) as bounty_total,
        coalesce(cs.avg_sentiment,0) as avg_comment_sentiment,
        coalesce(cs.comment_count,0) as comment_count,
        qm.answers_7d,
        qm.answers_30d,
        qm.max_answer_score_30d,
        qm.fastest_answer_minutes,
        qm.has_accepted,
        qm.is_closed,
        qm.is_community
    from question_meta qm
    left join vote_agg va on va.postid = qm.question_id
    left join comment_sentiment cs on cs.postid = qm.question_id
),
quality_score as (
    select
        pe.*,
        (
            0.4 * coalesce(nullif(pe.question_score,0), ln(1 + greatest(pe.upvotes - pe.downvotes,0)))
          + 0.2 * ln(1 + pe.viewcount)
          + 0.15 * coalesce(pe.avg_comment_sentiment,0)
          + 0.1 * coalesce(pe.favorites_votes,0)
          + 0.1 * coalesce(pe.answers_30d,0)
          + 0.05 * case when pe.has_accepted = 1 then 5 else 0 end
          - 0.1 * case when pe.is_closed = 1 then 5 else 0 end
        ) as composite_quality
    from post_enriched pe
),
user_quality as (
    select
        ua.user_id,
        ua.displayname,
        ua.reputation,
        ua.cohort_month,
        ua.questions_asked,
        ua.questions_with_accept,
        ua.avg_fastest_answer_min,
        ua.answers_within_7d_total,
        ua.answers_within_30d_total,
        ua.avg_question_score,
        ua.avg_views,
        count(qs.question_id) as qs_count,
        avg(qs.composite_quality) as avg_quality,
        percentile_cont(0.9) within group (order by qs.composite_quality) as p90_quality
    from user_activity ua
    left join quality_score qs on qs.asker_id = ua.user_id
    group by ua.user_id, ua.displayname, ua.reputation, ua.cohort_month, ua.questions_asked, ua.questions_with_accept, ua.avg_fastest_answer_min, ua.answers_within_7d_total, ua.answers_within_30d_total, ua.avg_question_score, ua.avg_views
),
duplicate_map as (
    select
        pl.relatedpostid as canonical_id,
        pl.postid as duplicate_id,
        min(pl.creationdate) as first_seen
    from postlinks pl
    where pl.linktypeid = 3
    group by pl.relatedpostid, pl.postid
),
dup_enriched as (
    select
        qs.question_id,
        case when exists (select 1 from duplicate_map dm where dm.duplicate_id = qs.question_id) then 1 else 0 end as is_marked_duplicate,
        (select count(*) from duplicate_map dm where dm.canonical_id = qs.question_id) as duplicates_pointing_here
    from quality_score qs
),
final as (
    select
        uq.user_id,
        uq.displayname,
        uq.reputation,
        uq.cohort_month,
        uq.questions_asked,
        uq.questions_with_accept,
        uq.avg_fastest_answer_min,
        uq.answers_within_7d_total,
        uq.answers_within_30d_total,
        uq.avg_question_score,
        uq.avg_views,
        uq.qs_count,
        uq.avg_quality,
        uq.p90_quality,
        sum(case when de.is_marked_duplicate = 1 then 1 else 0 end) as dup_questions_by_user,
        sum(coalesce(de.duplicates_pointing_here,0)) as canonical_popularity_by_user
    from user_quality uq
    left join quality_score qs on qs.asker_id = uq.user_id
    left join dup_enriched de on de.question_id = qs.question_id
    group by uq.user_id, uq.displayname, uq.reputation, uq.cohort_month, uq.questions_asked, uq.questions_with_accept, uq.avg_fastest_answer_min, uq.answers_within_7d_total, uq.answers_within_30d_total, uq.avg_question_score, uq.avg_views, uq.qs_count, uq.avg_quality, uq.p90_quality
),
cohort_ranked as (
    select
        f.*,
        row_number() over (partition by f.cohort_month order by f.avg_quality desc nulls last, f.qs_count desc) as cohort_rank,
        rank() over (order by f.avg_quality desc nulls last) as global_rank,
        ntile(10) over (order by f.avg_quality desc nulls last) as decile
    from final f
)
select
    cr.cohort_month,
    cr.global_rank,
    cr.cohort_rank,
    cr.decile,
    cr.user_id,
    coalesce(nullif(cr.displayname,''), ('user_' || cast(cr.user_id as varchar))) as displayname,
    cr.reputation,
    cr.questions_asked,
    cr.questions_with_accept,
    round(cast(coalesce(cr.avg_fastest_answer_min,0) as numeric), 2) as avg_fastest_answer_min,
    cr.answers_within_7d_total,
    cr.answers_within_30d_total,
    round(cast(coalesce(cr.avg_question_score,0) as numeric), 2) as avg_question_score,
    round(cast(coalesce(cr.avg_views,0) as numeric), 2) as avg_views,
    cr.qs_count as quality_scored_questions,
    round(cast(coalesce(cr.avg_quality,0) as numeric), 3) as avg_quality,
    round(cast(coalesce(cr.p90_quality,0) as numeric), 3) as p90_quality,
    coalesce(cr.dup_questions_by_user,0) as dup_questions_by_user,
    coalesce(cr.canonical_popularity_by_user,0) as canonical_popularity_by_user
from cohort_ranked cr
where cr.qs_count >= least(10, greatest(3, (select avg(qs_count) from final)))
  and (cr.avg_quality > 0 or cr.reputation > 1000)
order by cr.cohort_month desc, cr.cohort_rank asc
limit 500;