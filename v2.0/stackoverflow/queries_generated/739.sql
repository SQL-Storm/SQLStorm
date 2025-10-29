-- {"query": "739.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3406} 
with
params as (
    select
        date_trunc('month', now()) - interval '24 months' as start_month,
        now() as now_ts
),
-- Normalize tags and select recent questions
recent_questions as (
    select
        p.Id as question_id,
        p.OwnerUserId as asker_id,
        p.CreationDate as q_created,
        p.Score as q_score,
        p.ViewCount as q_views,
        p.AnswerCount as q_answer_count,
        p.AcceptedAnswerId,
        p.Tags,
        regexp_split_to_table(coalesce(substring(p.Tags from 2 for length(p.Tags)-2), ''), '><') as tag
    from Posts p
    join PostTypes pt on pt.Id = p.PostTypeId and pt.Name = 'Question'
    cross join params
    where p.CreationDate >= params.start_month
),
-- Aggregate per-question stats
question_stats as (
    select
        rq.question_id,
        rq.asker_id,
        rq.q_created,
        rq.q_score,
        rq.q_views,
        rq.q_answer_count,
        rq.AcceptedAnswerId,
        array_agg(distinct lower(rq.tag) order by lower(rq.tag)) filter (where rq.tag is not null and rq.tag <> '') as tags_array,
        count(*) filter (where rq.tag is not null and rq.tag <> '') as tag_count
    from recent_questions rq
    group by rq.question_id, rq.asker_id, rq.q_created, rq.q_score, rq.q_views, rq.q_answer_count, rq.AcceptedAnswerId
),
-- Answers for those questions
answers as (
    select
        a.Id as answer_id,
        a.ParentId as question_id,
        a.OwnerUserId as answerer_id,
        a.Score as a_score,
        a.CreationDate as a_created
    from Posts a
    join PostTypes pt on pt.Id = a.PostTypeId and pt.Name = 'Answer'
),
-- Compute first/fastest answer and accepted answer metrics
answer_metrics as (
    select
        qs.question_id,
        min(a.a_created) as first_answer_time,
        max(a.a_created) filter (where a.a_score > 0) as last_pos_answer_time,
        avg(a.a_score::numeric) as avg_answer_score,
        sum(case when a.answer_id = qs.AcceptedAnswerId then 1 else 0 end) as has_accepted,
        min(a.answer_id) filter (where a.a_created = min(a.a_created) over (partition by a.question_id)) as first_answer_id,
        count(*) as total_answers
    from question_stats qs
    left join answers a on a.question_id = qs.question_id
    group by qs.question_id
),
-- Comments on questions and answers
post_comments as (
    select
        c.PostId,
        count(*) as comment_count,
        sum(c.Score) as comment_score_sum,
        max(c.CreationDate) as last_comment_time
    from Comments c
    group by c.PostId
),
-- Votes aggregated with selective filters and NULL-safe handling
vote_agg as (
    select
        v.PostId,
        count(*) filter (where vt.Name = 'UpMod') as upvotes,
        count(*) filter (where vt.Name = 'DownMod') as downvotes,
        count(*) filter (where vt.Name = 'Favorite') as favorites,
        count(*) filter (where vt.Name = 'AcceptedByOriginator') as accepted_marks,
        sum(v.BountyAmount) filter (where vt.Name in ('BountyStart', 'BountyClose')) as bounty_sum
    from Votes v
    join VoteTypes vt on vt.Id = v.VoteTypeId
    group by v.PostId
),
-- Link relationships to detect duplicates and related posts
link_agg as (
    select
        pl.PostId as question_id,
        count(*) filter (where lt.Name = 'Duplicate') as dup_links,
        count(*) filter (where lt.Name = 'Linked') as linked_links,
        max(pl.CreationDate) filter (where lt.Name = 'Duplicate') as last_dup_link
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    group by pl.PostId
),
-- Post history to determine closes and reopen events and reasons
close_reopen as (
    select
        ph.PostId as question_id,
        min(ph.CreationDate) filter (where pht.Name = 'Post Closed') as first_closed_at,
        max(ph.CreationDate) filter (where pht.Name = 'Post Reopened') as last_reopened_at,
        max(crt.Name) filter (where pht.Name = 'Post Closed') as last_close_reason_name,
        count(*) filter (where pht.Name = 'Post Closed') as close_events,
        count(*) filter (where pht.Name = 'Post Reopened') as reopen_events
    from PostHistory ph
    left join PostHistoryTypes pht on pht.Id = ph.PostHistoryTypeId
    left join CloseReasonTypes crt on crt.Id::varchar = nullif(ph.Comment,'') -- Comment contains CloseReasonId for type 10
    group by ph.PostId
),
-- User aggregates: activity and reputation bands
user_agg as (
    select
        u.Id as user_id,
        u.DisplayName,
        u.Reputation,
        width_bucket(u.Reputation, 0, 100000, 5) as rep_bucket,
        extract(year from u.CreationDate) as user_cohort_year,
        coalesce(u.Location, 'Unknown') as location_norm,
        count(b.Id) filter (where b.Class = 1) as gold_badges,
        count(b.Id) filter (where b.Class = 2) as silver_badges,
        count(b.Id) filter (where b.Class = 3) as bronze_badges,
        max(b.Date) as last_badge_date
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location
),
-- Tag popularity snapshot
tag_popularity as (
    select
        lower(t.TagName) as tag,
        t.Count as tag_total_count,
        t.IsModeratorOnly::int as is_mod_only,
        t.IsRequired::int as is_required
    from Tags t
),
-- Explode tags per question for set-based tag stats
question_tag_expanded as (
    select
        qs.question_id,
        unnest(qs.tags_array) as tag
    from question_stats qs
),
tag_enriched as (
    select
        qte.question_id,
        qte.tag,
        tp.tag_total_count,
        tp.is_mod_only,
        tp.is_required
    from question_tag_expanded qte
    left join tag_popularity tp on tp.tag = qte.tag
),
-- Compute per-question tag metrics
per_question_tag_stats as (
    select
        question_id,
        count(*) as tags_used,
        sum(case when tag_total_count is null then 1 else 0 end) as unseen_tags,
        avg(tag_total_count::numeric) as avg_tag_popularity,
        max(tag_total_count) as max_tag_popularity,
        sum(is_mod_only) as mod_only_count,
        sum(is_required) as required_count
    from tag_enriched
    group by question_id
),
-- Build a dense time series per month to join against question creation
months as (
    select generate_series(
        (select start_month from params),
        (select now_ts from params),
        interval '1 month'
    )::date as month_start
),
-- Per-month aggregates using window functions and set operators
monthly_question_activity as (
    select
        date_trunc('month', qs.q_created)::date as month_start,
        count(*) as questions,
        sum(case when am.has_accepted > 0 then 1 else 0 end) as with_accepted,
        avg(qs.q_score::numeric) as avg_q_score,
        percentile_cont(0.5) within group (order by coalesce(qs.q_views,0)) as median_views,
        avg(extract(epoch from (am.first_answer_time - qs.q_created)) / 3600.0) as avg_hours_to_first_answer
    from question_stats qs
    left join answer_metrics am on am.question_id = qs.question_id
    group by date_trunc('month', qs.q_created)
),
-- Combine months to ensure gaps are visible
monthly_series as (
    select
        m.month_start,
        coalesce(mqa.questions, 0) as questions,
        coalesce(mqa.with_accepted, 0) as with_accepted,
        mqa.avg_q_score,
        mqa.median_views,
        mqa.avg_hours_to_first_answer
    from months m
    left join monthly_question_activity mqa on mqa.month_start = m.month_start
),
-- Correlated subquery to compute user's rolling activity window
user_recent_activity as (
    select
        ua.user_id,
        (
            select count(*)
            from Posts p
            where p.OwnerUserId = ua.user_id
              and p.CreationDate >= (select start_month from params)
        ) as posts_since_start,
        (
            select count(distinct date_trunc('month', p.CreationDate))
            from Posts p
            where p.OwnerUserId = ua.user_id
              and p.CreationDate >= (select start_month from params)
        ) as active_months
    from user_agg ua
),
-- Detect questions with inconsistent accepted answer marks via set operator
accepted_inconsistency as (
    select qs.question_id
    from question_stats qs
    left join answer_metrics am on am.question_id = qs.question_id
    where (qs.AcceptedAnswerId is not null and coalesce(am.has_accepted,0) = 0)
    union
    select qs.question_id
    from question_stats qs
    left join answer_metrics am on am.question_id = qs.question_id
    where (qs.AcceptedAnswerId is null and coalesce(am.has_accepted,0) > 0)
),
-- Bring it all together
final as (
    select
        qs.question_id,
        qs.q_created,
        qs.q_score,
        qs.q_views,
        qs.q_answer_count,
        qs.tags_array,
        pqt.tags_used,
        pqt.unseen_tags,
        pqt.avg_tag_popularity,
        pqt.max_tag_popularity,
        pqt.mod_only_count,
        pqt.required_count,
        coalesce(am.total_answers, 0) as total_answers,
        (am.has_accepted > 0) as has_accepted,
        am.first_answer_time,
        am.last_pos_answer_time,
        u.DisplayName as asker_name,
        ua.Reputation as asker_rep,
        ua.rep_bucket,
        ua.user_cohort_year,
        ua.location_norm,
        ua.gold_badges,
        ua.silver_badges,
        ua.bronze_badges,
        ura.posts_since_start,
        ura.active_months,
        coalesce(vq.upvotes,0) as q_upvotes,
        coalesce(vq.downvotes,0) as q_downvotes,
        coalesce(vq.favorites,0) as q_favorites,
        coalesce(vq.bounty_sum,0) as q_bounty_sum,
        coalesce(pcq.comment_count,0) as q_comment_count,
        coalesce(pcq.comment_score_sum,0) as q_comment_score_sum,
        pcq.last_comment_time as q_last_comment_time,
        coalesce(la.dup_links,0) as dup_links,
        coalesce(la.linked_links,0) as linked_links,
        la.last_dup_link,
        cr.first_closed_at,
        cr.last_reopened_at,
        cr.last_close_reason_name,
        cr.close_events,
        cr.reopen_events,
        (ai.question_id is not null) as accepted_mismatch_flag,
        -- composite complexity score
        (
            coalesce(qs.q_score,0)
            + coalesce(vq.upvotes,0)*0.5
            - coalesce(vq.downvotes,0)*0.75
            + coalesce(vq.favorites,0)*0.25
            + least(coalesce(qs.q_views,0)::numeric, 50000)/5000
            + coalesce(am.total_answers,0)*0.4
            + case when am.has_accepted > 0 then 2 else 0 end
            + coalesce(pqt.mod_only_count,0)*(-1)
            + case when cr.first_closed_at is not null then -2 else 0 end
        )::numeric(12,4) as complexity_score,
        -- string expressions
        coalesce('[' || array_to_string(qs.tags_array, ',') || ']', '[no-tags]') as tags_rendered,
        trim(both ' ' from coalesce(u.DisplayName, 'user-' || qs.asker_id::text)) as asker_label,
        -- null/boolean logic example
        case
            when cr.first_closed_at is not null and cr.last_reopened_at is null then 'Closed'
            when cr.first_closed_at is not null and cr.last_reopened_at >= cr.first_closed_at then 'Reopened'
            when cr.first_closed_at is null then 'Open'
            else 'Unknown'
        end as closure_state
    from question_stats qs
    left join per_question_tag_stats pqt on pqt.question_id = qs.question_id
    left join answer_metrics am on am.question_id = qs.question_id
    left join Users u on u.Id = qs.asker_id
    left join user_agg ua on ua.user_id = qs.asker_id
    left join user_recent_activity ura on ura.user_id = qs.asker_id
    left join vote_agg vq on vq.PostId = qs.question_id
    left join post_comments pcq on pcq.PostId = qs.question_id
    left join link_agg la on la.question_id = qs.question_id
    left join close_reopen cr on cr.question_id = qs.question_id
    left join accepted_inconsistency ai on ai.question_id = qs.question_id
),
-- Rank and window aggregates across final dataset
scored as (
    select
        f.*,
        row_number() over (order by f.complexity_score desc, f.q_created desc) as rn_global,
        rank() over (partition by date_trunc('month', f.q_created) order by f.complexity_score desc) as rnk_in_month,
        avg(f.complexity_score) over (partition by date_trunc('month', f.q_created)) as avg_score_month,
        avg(f.complexity_score) over () as avg_score_all,
        percentile_cont(0.9) within group (order by f.complexity_score) over () as p90_score_all
    from final f
)
select
    s.question_id,
    s.q_created,
    s.asker_label,
    s.tags_rendered,
    s.q_score,
    s.q_views,
    s.q_answer_count,
    s.total_answers,
    s.has_accepted,
    s.first_answer_time,
    s.q_upvotes,
    s.q_downvotes,
    s.q_favorites,
    s.dup_links,
    s.closure_state,
    s.complexity_score,
    s.rn_global,
    s.rnk_in_month,
    s.avg_score_month,
    s.avg_score_all,
    s.p90_score_all
from scored s
where
    -- predicate to exercise planner with expressions and null-safe logic
    (coalesce(s.q_views,0) > 100 or (s.q_score > 5 and coalesce(s.total_answers,0) >= 1))
    and (s.first_answer_time is null or s.first_answer_time - s.q_created >= interval '0 hours')
    and (s.accepted_mismatch_flag is true or s.complexity_score > s.avg_score_month)
order by
    s.complexity_score desc nulls last,
    s.q_created desc
limit 250;