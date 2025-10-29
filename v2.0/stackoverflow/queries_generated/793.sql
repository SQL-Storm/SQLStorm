-- {"query": "793.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3129} 
with params as (
    select
        date_trunc('month', (now() - interval '24 months')) as start_month,
        now() as as_of,
        10 as top_n
),
months as (
    select generate_series((select start_month from params), (select date_trunc('month', as_of) from params), interval '1 month')::date as month_start
),
questions as (
    select
        p.Id as question_id,
        p.CreationDate::date as created_date,
        date_trunc('month', p.CreationDate)::date as month_start,
        p.Score,
        coalesce(p.ViewCount, 0) as views,
        p.OwnerUserId as owner_id,
        p.Tags,
        p.Title,
        p.ClosedDate,
        p.AcceptedAnswerId,
        case when p.Tags is not null and length(p.Tags) > 2 then string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><') else array[]::varchar[] end as tag_arr
    from Posts p
    where p.PostTypeId = 1
      and p.CreationDate >= (select start_month from params)
),
answers as (
    select
        a.Id as answer_id,
        a.ParentId as question_id,
        a.OwnerUserId as owner_id,
        a.CreationDate,
        a.Score as answer_score,
        row_number() over (partition by a.ParentId order by a.Score desc nulls last, a.CreationDate asc) as rn_by_score,
        min(a.CreationDate) over (partition by a.ParentId) as first_answer_time
    from Posts a
    where a.PostTypeId = 2
),
q_activity as (
    select
        q.question_id,
        q.month_start,
        count(ans.answer_id) as answer_count,
        max(case when ans.rn_by_score = 1 then ans.answer_id end) as top_answer_id,
        max(case when ans.rn_by_score = 1 then ans.answer_score end) as top_answer_score,
        min(ans.CreationDate) as first_answer_at,
        max(ans.CreationDate) as last_answer_at
    from questions q
    left join answers ans on ans.question_id = q.question_id
    group by q.question_id, q.month_start
),
votes_agg as (
    select
        v.PostId as post_id,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as upvotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as downvotes,
        sum(case when v.VoteTypeId = 5 then 1 else 0 end) as favorites,
        count(*) filter (where v.VoteTypeId in (2,3)) as total_votes,
        min(v.CreationDate) filter (where v.VoteTypeId in (2,3)) as first_vote_at
    from Votes v
    where v.CreationDate >= (select start_month from params)
    group by v.PostId
),
comment_agg as (
    select
        c.PostId as post_id,
        count(*) as comment_count,
        sum(coalesce(c.Score,0)) as comment_score_sum,
        max(c.CreationDate) as last_comment_at
    from Comments c
    where c.CreationDate >= (select start_month from params)
    group by c.PostId
),
dupe_links as (
    select
        pl.PostId as duplicate_of_id,
        pl.RelatedPostId as original_id,
        pl.CreationDate,
        row_number() over (partition by pl.PostId order by pl.CreationDate asc) as rn
    from PostLinks pl
    where pl.LinkTypeId = 3
),
closures as (
    select
        ph.PostId as post_id,
        min(ph.CreationDate) as first_closed_at,
        max(ph.CreationDate) as last_closed_at,
        count(*) as close_events,
        max(nullif(trim(ph.Comment), '')) as last_close_reason_code
    from PostHistory ph
    where ph.PostHistoryTypeId = 10
    group by ph.PostId
),
users_norm as (
    select
        u.Id,
        u.DisplayName,
        coalesce(nullif(trim(u.Location), ''), 'Unknown') as Location,
        case when u.Views is null then 0 else u.Views end as Views,
        u.Reputation,
        coalesce(u.UpVotes,0) as UpVotes,
        coalesce(u.DownVotes,0) as DownVotes,
        greatest(1, nullif(u.UpVotes + u.DownVotes, 0)) as vote_activity_den
    from Users u
),
user_badges as (
    select
        b.UserId,
        count(*) as badges_total,
        sum(case when b.Class = 1 then 1 else 0 end) as gold,
        sum(case when b.Class = 2 then 1 else 0 end) as silver,
        sum(case when b.Class = 3 then 1 else 0 end) as bronze,
        max(b.Date) as last_badge_at
    from Badges b
    group by b.UserId
),
tag_expanded as (
    select
        q.question_id,
        lower(trim(t)) as tag
    from questions q
    cross join unnest(q.tag_arr) as t
),
tag_stats as (
    select
        te.tag,
        count(distinct te.question_id) as tag_questions,
        sum(coalesce(q.Score,0)) as tag_score_sum,
        sum(coalesce(q.views,0)) as tag_views_sum
    from tag_expanded te
    join questions q on q.question_id = te.question_id
    group by te.tag
),
hot_candidates as (
    select
        q.question_id,
        q.month_start,
        q.Score,
        q.views,
        qa.answer_count,
        qa.first_answer_at,
        qa.last_answer_at,
        v.upvotes,
        v.downvotes,
        v.favorites,
        v.total_votes,
        v.first_vote_at,
        c.comment_count,
        c.comment_score_sum,
        c.last_comment_at,
        cl.first_closed_at,
        cl.last_closed_at,
        cl.close_events,
        cl.last_close_reason_code,
        u.Id as owner_id,
        u.DisplayName,
        u.Location,
        u.Reputation,
        u.Views as profile_views,
        ub.badges_total,
        ub.gold,
        ub.silver,
        ub.bronze,
        ub.last_badge_at,
        tps.tag_score_sum,
        tps.tag_views_sum,
        tps.tag_questions,
        d.original_id as duplicate_of_question_id,
        (case when q.AcceptedAnswerId is not null then 1 else 0 end) as has_accepted,
        (case when q.ClosedDate is not null then 1 else 0 end) as is_closed,
        coalesce(v.upvotes - v.downvotes, 0) as net_votes,
        (coalesce(q.views,0) / nullif(extract(epoch from (now() - q.CreationDate)) / 3600.0, 0)) as views_per_hour,
        (coalesce(v.total_votes,0) / nullif(extract(epoch from (now() - coalesce(v.first_vote_at, q.CreationDate))) / 86400.0, 0)) as votes_per_day_since_first_vote,
        (coalesce(c.comment_count,0)::numeric / nullif(extract(epoch from (now() - coalesce(c.last_comment_at, q.CreationDate))) / 86400.0, 0)) as comments_decay_rate,
        (coalesce(qa.answer_count,0) + coalesce(v.upvotes,0) + greatest(0, coalesce(c.comment_score_sum,0)))::numeric
            / nullif(1 + power(2, greatest(0, date_part('day', now() - q.CreationDate)::int)), 0) as activity_cooloff_score
    from questions q
    left join q_activity qa on qa.question_id = q.question_id and qa.month_start = q.month_start
    left join votes_agg v on v.post_id = q.question_id
    left join comment_agg c on c.post_id = q.question_id
    left join closures cl on cl.post_id = q.question_id
    left join users_norm u on u.Id = q.owner_id
    left join user_badges ub on ub.UserId = q.owner_id
    left join lateral (
        select
            avg(ts.tag_score_sum) as tag_score_sum,
            avg(ts.tag_views_sum) as tag_views_sum,
            avg(ts.tag_questions) as tag_questions
        from tag_expanded te
        join tag_stats ts on ts.tag = te.tag
        where te.question_id = q.question_id
    ) tps on true
    left join lateral (
        select original_id
        from dupe_links d
        where d.duplicate_of_id = q.question_id
        order by d.rn
        limit 1
    ) d on true
),
ranked as (
    select
        hc.*,
        dense_rank() over (
            partition by hc.month_start
            order by
                (coalesce(hc.Score,0) * 0.35)
              + (coalesce(hc.net_votes,0) * 0.25)
              + (coalesce(hc.answer_count,0) * 0.15)
              + (coalesce(hc.views_per_hour,0) * 0.10)
              + (coalesce(hc.activity_cooloff_score,0) * 0.10)
              + (case when hc.is_closed = 1 then -5 else 0 end)
              + (case when hc.duplicate_of_question_id is not null then -3 else 0 end)
              + least(coalesce(hc.tag_views_sum,0) / nullif(coalesce(hc.tag_questions,1),0), 100000)::numeric * 0.05 desc,
                hc.question_id
        ) as dense_rnk,
        row_number() over (
            partition by hc.month_start
            order by
                (coalesce(hc.Score,0) * 0.35)
              + (coalesce(hc.net_votes,0) * 0.25)
              + (coalesce(hc.answer_count,0) * 0.15)
              + (coalesce(hc.views_per_hour,0) * 0.10)
              + (coalesce(hc.activity_cooloff_score,0) * 0.10)
              + (case when hc.is_closed = 1 then -5 else 0 end)
              + (case when hc.duplicate_of_question_id is not null then -3 else 0 end)
              + least(coalesce(hc.tag_views_sum,0) / nullif(coalesce(hc.tag_questions,1),0), 100000)::numeric * 0.05 desc,
                hc.question_id
        ) as row_rnk
    from hot_candidates hc
),
monthly_top as (
    select
        r.*
    from ranked r
    where r.row_rnk <= (select top_n from params)
),
summary_by_month as (
    select
        m.month_start,
        count(mt.question_id) as top_questions,
        avg(mt.Score) as avg_score,
        percentile_cont(0.5) within group (order by mt.views) as median_views,
        sum(case when mt.is_closed = 1 then 1 else 0 end) as closed_in_top,
        sum(case when mt.has_accepted = 1 then 1 else 0 end) as accepted_in_top,
        avg(mt.net_votes) as avg_net_votes,
        max(mt.views_per_hour) as max_vph
    from months m
    left join monthly_top mt on mt.month_start = m.month_start
    group by m.month_start
),
orphan_months as (
    select m.month_start
    from months m
    where not exists (
        select 1 from monthly_top mt where mt.month_start = m.month_start
    )
),
final_union as (
    select
        to_char(mt.month_start, 'YYYY-MM') as month_key,
        'TOP' as row_type,
        mt.question_id,
        coalesce(mt.Title, '[no title]') as title,
        mt.DisplayName as owner,
        mt.Location as owner_location,
        mt.Score,
        mt.views,
        mt.answer_count,
        mt.net_votes,
        mt.views_per_hour,
        mt.votes_per_day_since_first_vote,
        mt.comments_decay_rate,
        mt.is_closed,
        mt.has_accepted,
        mt.dense_rnk as rank_in_month,
        mt.duplicate_of_question_id,
        mt.first_answer_at,
        mt.last_answer_at,
        mt.first_vote_at,
        mt.last_comment_at,
        mt.first_closed_at,
        mt.last_closed_at
    from monthly_top mt
    union all
    select
        to_char(sbm.month_start, 'YYYY-MM') as month_key,
        'SUMMARY' as row_type,
        null::int as question_id,
        null::varchar as title,
        null::varchar as owner,
        null::varchar as owner_location,
        null::int as Score,
        sbm.median_views::int as views,
        sbm.top_questions as answer_count,
        sbm.avg_net_votes::int as net_votes,
        sbm.max_vph as views_per_hour,
        null::numeric as votes_per_day_since_first_vote,
        null::numeric as comments_decay_rate,
        null::int as is_closed,
        null::int as has_accepted,
        null::int as rank_in_month,
        null::int as duplicate_of_question_id,
        null::timestamp as first_answer_at,
        null::timestamp as last_answer_at,
        null::timestamp as first_vote_at,
        null::timestamp as last_comment_at,
        null::timestamp as first_closed_at,
        null::timestamp as last_closed_at
    from summary_by_month sbm
    union all
    select
        to_char(o.month_start, 'YYYY-MM') as month_key,
        'EMPTY' as row_type,
        null, null, null, null, null, null, null, null,
        null::numeric, null::numeric, null::int, null::int, null::int, null::int,
        null::timestamp, null::timestamp, null::timestamp, null::timestamp, null::timestamp, null::timestamp
    from orphan_months o
)
select *
from final_union
order by month_key desc, row_type, rank_in_month nulls last, question_id nulls last;