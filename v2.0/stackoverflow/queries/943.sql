-- {"query": "943.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2998} 
with params as (
    select
        date_trunc('month', cast('2024-10-01 12:34:56' as timestamp)) - interval '24 months' as start_month,
        date_trunc('month', cast('2024-10-01 12:34:56' as timestamp)) - interval '1 month'  as end_month
),
month_grid as (
    select generate_series(p.start_month, p.end_month, interval '1 month')::date as month_start
    from params p
),
questions as (
    select
        q.Id,
        q.CreationDate::date as created_on,
        date_trunc('month', q.CreationDate)::date as month_start,
        q.Score,
        q.ViewCount,
        q.OwnerUserId,
        q.AcceptedAnswerId,
        q.Title,
        q.Tags,
        q.FavoriteCount,
        q.CommentCount
    from Posts q
    where q.PostTypeId = 1
      and q.CreationDate >= (select start_month from params)
      and q.CreationDate <  (select end_month from params) + interval '1 month'
),
answers as (
    select
        a.Id,
        a.ParentId as QuestionId,
        a.OwnerUserId,
        a.CreationDate,
        a.Score
    from Posts a
    where a.PostTypeId = 2
),
first_answer as (
    select
        a.QuestionId,
        min(a.CreationDate) as first_answer_time,
        count(*) filter (where a.Score > 0) as pos_answer_count
    from answers a
    group by a.QuestionId
),
votes_agg as (
    select
        v.PostId,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as upvotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as downvotes,
        sum(case when v.VoteTypeId = 8 then 1 else 0 end) as bounty_starts,
        sum(case when v.VoteTypeId = 9 then 1 else 0 end) as bounty_closes,
        sum(coalesce(v.BountyAmount,0)) as bounty_amount_total
    from Votes v
    where v.CreationDate >= (select start_month from params)
      and v.CreationDate <  (select end_month from params) + interval '1 month'
    group by v.PostId
),
comments_agg as (
    select
        c.PostId,
        count(*) as comment_count,
        sum(c.Score) as comment_score_sum,
        max(c.CreationDate) as last_comment_at
    from Comments c
    where c.CreationDate >= (select start_month from params)
      and c.CreationDate <  (select end_month from params) + interval '1 month'
    group by c.PostId
),
dup_links as (
    select
        pl.PostId,
        count(*) filter (where pl.LinkTypeId = 3) as dup_link_count,
        count(*) filter (where pl.LinkTypeId = 1) as linked_count
    from PostLinks pl
    where pl.CreationDate >= (select start_month from params)
      and pl.CreationDate <  (select end_month from params) + interval '1 month'
    group by pl.PostId
),
close_events as (
    select
        ph.PostId,
        count(*) filter (where ph.PostHistoryTypeId = 10) as close_votes_events,
        count(*) filter (where ph.PostHistoryTypeId = 11) as reopen_events,
        max(ph.CreationDate) filter (where ph.PostHistoryTypeId = 10) as last_close_event_at,
        max(ph.CreationDate) filter (where ph.PostHistoryTypeId = 11) as last_reopen_event_at,
        max(
            nullif(
                regexp_replace(
                    nullif(ph.Comment, ''),
                    '[^0-9]', '',
                    'g'
                ),
                ''
            )::int
        ) filter (where ph.PostHistoryTypeId = 10) as last_close_reason_id
    from PostHistory ph
    where ph.CreationDate >= (select start_month from params)
      and ph.CreationDate <  (select end_month from params) + interval '1 month'
    group by ph.PostId
),
tag_expansion as (
    select
        q.Id as QuestionId,
        unnest(string_to_array(substring(q.Tags, 2, length(q.Tags)-2), '><')) as tag_name
    from questions q
    where q.Tags is not null
),
tag_quality as (
    select
        t.tag_name,
        count(distinct te.QuestionId) as tagged_questions,
        avg(q.Score) as avg_q_score,
        percentile_cont(0.5) within group (order by coalesce(q.ViewCount,0)) as median_views
    from tag_expansion te
    join questions q on q.Id = te.QuestionId
    join lateral (select te.tag_name) t on true
    group by t.tag_name
),
user_quality as (
    select
        u.Id as UserId,
        u.Reputation,
        u.UpVotes,
        u.DownVotes,
        u.Views,
        coalesce(nullif(trim(u.Location), ''), 'Unknown') as location_norm,
        date_trunc('year', u.CreationDate)::date as join_year,
        row_number() over (partition by coalesce(nullif(trim(u.Location), ''), 'Unknown') order by u.Reputation desc, u.Id) as loc_rank
    from Users u
),
accepted_stats as (
    select
        q.Id as QuestionId,
        case when q.AcceptedAnswerId is not null then 1 else 0 end as has_accepted,
        a.Score as accepted_answer_score
    from questions q
    left join Posts a on a.Id = q.AcceptedAnswerId
),
question_rollup as (
    select
        mg.month_start,
        q.Id as QuestionId,
        q.OwnerUserId,
        q.Score,
        q.ViewCount,
        q.Title,
        q.Tags,
        q.FavoriteCount,
        q.CommentCount,
        coalesce(v.upvotes,0) as upvotes,
        coalesce(v.downvotes,0) as downvotes,
        coalesce(v.bounty_starts,0) as bounty_starts,
        coalesce(v.bounty_closes,0) as bounty_closes,
        coalesce(v.bounty_amount_total,0) as bounty_amount_total,
        coalesce(ca.comment_count,0) as comment_count_recent,
        coalesce(ca.comment_score_sum,0) as comment_score_sum_recent,
        ca.last_comment_at,
        coalesce(dl.dup_link_count,0) as dup_links_recent,
        coalesce(dl.linked_count,0) as linked_count_recent,
        coalesce(ce.close_votes_events,0) as close_events_recent,
        coalesce(ce.reopen_events,0) as reopen_events_recent,
        ce.last_close_event_at,
        ce.last_reopen_event_at,
        ce.last_close_reason_id,
        fa.first_answer_time,
        fa.pos_answer_count,
        acc.has_accepted,
        acc.accepted_answer_score
    from month_grid mg
    left join questions q on q.month_start = mg.month_start
    left join votes_agg v on v.PostId = q.Id
    left join comments_agg ca on ca.PostId = q.Id
    left join dup_links dl on dl.PostId = q.Id
    left join close_events ce on ce.PostId = q.Id
    left join first_answer fa on fa.QuestionId = q.Id
    left join accepted_stats acc on acc.QuestionId = q.Id
),
location_enriched as (
    select
        qr.*,
        uq.location_norm,
        uq.Reputation as asker_rep,
        uq.loc_rank as asker_loc_rank
    from question_rollup qr
    left join user_quality uq on uq.UserId = qr.OwnerUserId
),
time_to_first_answer as (
    select
        QuestionId,
        extract(epoch from (first_answer_time - (select min(q2.CreationDate) from Posts q2 where q2.Id = QuestionId and q2.PostTypeId = 1)))/3600.0 as hours_to_first_answer
    from first_answer
),
final_scores as (
    select
        le.*,
        tfa.hours_to_first_answer,
        case
            when le.Score is null then 0
            when le.ViewCount is null or le.ViewCount = 0 then le.Score
            else le.Score::numeric / nullif(le.ViewCount,0)
        end as score_per_view,
        case
            when le.has_accepted = 1 then greatest(0.0, 1.0 - coalesce(tfa.hours_to_first_answer, 999999)::numeric / 168.0)
            else 0.0
        end as acceptance_timeliness,
        case
            when coalesce(le.dup_links_recent,0) > 0 or coalesce(le.last_close_reason_id,0) in (101)
                then 1
            when coalesce(le.last_close_reason_id,0) in (102,103,104,105)
                then 0.8
            else 0
        end as duplication_signal,
        case
            when le.Tags is null then 'untagged'
            else lower(regexp_replace(coalesce(le.Tags,''), '[^a-zA-Z0-9<>-]', '', 'g'))
        end as tags_norm
    from location_enriched le
    left join time_to_first_answer tfa using (QuestionId)
),
ranked as (
    select
        fs.*,
        sum(coalesce(upvotes,0) - coalesce(downvotes,0)) over (partition by month_start) as net_votes_month_sum,
        row_number() over (partition by month_start order by (coalesce(upvotes,0) - coalesce(downvotes,0)) desc nulls last, ViewCount desc nulls last, QuestionId) as month_popularity_rank,
        dense_rank() over (order by coalesce(asker_rep,0) desc, coalesce(ViewCount,0) desc) as global_author_influence_rank
    from final_scores fs
),
tag_top as (
    select
        r.month_start,
        te.tag_name,
        r.QuestionId,
        r.Score,
        r.ViewCount,
        r.upvotes,
        r.downvotes,
        row_number() over (partition by r.month_start, te.tag_name order by coalesce(r.Score, -999999) desc, r.ViewCount desc) as tag_rank
    from ranked r
    join tag_expansion te on te.QuestionId = r.QuestionId
),
tag_top1 as (
    select *
    from tag_top
    where tag_rank <= 1
),
monthly_summary as (
    select
        r.month_start,
        count(*) as questions_in_month,
        avg(coalesce(r.Score,0)) as avg_score,
        sum(coalesce(r.ViewCount,0)) as total_views,
        avg(r.score_per_view) as avg_score_per_view,
        avg(r.acceptance_timeliness) as avg_accept_timeliness,
        sum(case when r.has_accepted = 1 then 1 else 0 end) as accepted_count,
        count(*) filter (where r.duplication_signal > 0) as flagged_dup_or_close,
        max(r.net_votes_month_sum) as net_votes_month_sum
    from ranked r
    group by r.month_start
),
unioned as (
    select
        'question' as row_type,
        r.month_start,
        r.QuestionId::text as key1,
        coalesce(r.Title, '(untitled)') as key2,
        r.month_popularity_rank as metric_a,
        r.global_author_influence_rank as metric_b,
        r.upvotes - r.downvotes as metric_c,
        r.score_per_view as metric_d,
        r.acceptance_timeliness as metric_e,
        r.duplication_signal as metric_f,
        r.asker_rep as metric_g,
        r.ViewCount as metric_h,
        r.location_norm as dim_a,
        r.tags_norm as dim_b
    from ranked r

    union all

    select
        'monthly' as row_type,
        ms.month_start,
        null,
        null,
        ms.questions_in_month,
        null,
        ms.net_votes_month_sum,
        ms.avg_score_per_view,
        ms.avg_accept_timeliness,
        null,
        null,
        ms.total_views,
        null,
        null
    from monthly_summary ms

    union all

    select
        'tag_top' as row_type,
        tt.month_start,
        tt.tag_name,
        tt.QuestionId::text,
        tt.Score,
        null,
        tt.upvotes - tt.downvotes,
        null,
        null,
        null,
        null,
        tt.ViewCount,
        null,
        null
    from tag_top1 tt
)
select
    u.row_type,
    u.month_start,
    u.key1,
    u.key2,
    u.metric_a,
    u.metric_b,
    u.metric_c,
    round(u.metric_d::numeric, 6) as metric_d,
    round(u.metric_e::numeric, 6) as metric_e,
    u.metric_f,
    u.metric_g,
    u.metric_h,
    u.dim_a,
    u.dim_b
from unioned u
where
    (
        u.row_type = 'question'
        and (
            (u.metric_a is not null and u.metric_a <= 50)
            or (u.metric_c is not null and u.metric_c >= 10)
            or (u.metric_d is not null and u.metric_d >= 0.02)
            or (u.metric_e is not null and u.metric_e >= 0.5)
        )
    )
    or u.row_type in ('monthly','tag_top')
order by
    u.month_start,
    case u.row_type when 'monthly' then 0 when 'question' then 1 else 2 end,
    coalesce(u.metric_a, 999999),
    coalesce(u.metric_c, -999999) desc,
    u.key1 nulls last;