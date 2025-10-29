-- {"query": "174.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2582} 
with
recent_questions as (
    select
        p.Id as QuestionId,
        p.CreationDate,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.Title,
        p.Tags,
        date_trunc('month', p.CreationDate) as month_bucket
    from Posts p
    where p.PostTypeId = 1
      and p.CreationDate >= now() - interval '365 days'
),
answer_stats as (
    select
        q.QuestionId,
        count(a.Id) filter (where a.PostTypeId = 2) as answer_count,
        sum(case when a.CreationDate <= q.CreationDate + interval '1 day' then 1 else 0 end) as answers_in_24h,
        max(a.Score) as max_answer_score,
        min(a.CreationDate) as first_answer_time,
        avg(a.Score) as avg_answer_score
    from recent_questions q
    left join Posts a
        on a.ParentId = q.QuestionId
    group by q.QuestionId
),
vote_aggs as (
    select
        v.PostId,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as upvotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as downvotes,
        sum(case when v.VoteTypeId = 10 then 1 else 0 end) as deletions,
        sum(case when v.VoteTypeId = 11 then 1 else 0 end) as undeletions,
        sum(case when v.VoteTypeId = 8 then coalesce(v.BountyAmount,0) else 0 end) as bounty_started,
        sum(case when v.VoteTypeId = 9 then coalesce(v.BountyAmount,0) else 0 end) as bounty_awarded,
        min(v.CreationDate) as first_vote_time,
        max(v.CreationDate) as last_vote_time
    from Votes v
    group by v.PostId
),
comment_aggs as (
    select
        c.PostId,
        count(*) as comment_count,
        max(c.Score) as max_comment_score,
        avg(c.Score) as avg_comment_score,
        string_agg(distinct coalesce(c.UserDisplayName, 'anon'), ',' order by coalesce(c.UserDisplayName, 'anon')) as commenters
    from Comments c
    group by c.PostId
),
close_events as (
    select
        ph.PostId,
        min(case when ph.PostHistoryTypeId = 10 then ph.CreationDate end) as first_closed_at,
        max(case when ph.PostHistoryTypeId = 11 then ph.CreationDate end) as last_reopened_at,
        max(case when ph.PostHistoryTypeId = 10 then ph.Comment end) as last_close_reason_id
    from PostHistory ph
    where ph.PostHistoryTypeId in (10,11)
    group by ph.PostId
),
dup_links as (
    select
        pl.PostId,
        count(*) filter (where pl.LinkTypeId = 3) as dup_link_count,
        count(*) filter (where pl.LinkTypeId = 1) as linked_count,
        max(case when pl.LinkTypeId = 3 then pl.CreationDate end) as last_dup_link_at
    from PostLinks pl
    group by pl.PostId
),
owner_dims as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate as UserCreated,
        u.LastAccessDate,
        u.UpVotes,
        u.DownVotes,
        coalesce(nullif(trim(u.Location), ''), 'Unknown') as LocationNorm,
        case when u.WebsiteUrl ilike '%github.com%' then 1 else 0 end as has_github
    from Users u
),
tag_expansion as (
    select
        q.QuestionId,
        unnest(string_to_array(substring(q.Tags, 2, length(q.Tags)-2), '><')) as tag
    from recent_questions q
    where q.Tags is not null
),
tag_quality as (
    select
        te.QuestionId,
        te.tag,
        t.Count as tag_global_count,
        dense_rank() over (partition by te.QuestionId order by coalesce(t.Count,0) desc, te.tag) as tag_pop_rank
    from tag_expansion te
    left join Tags t
      on lower(t.TagName) = lower(te.tag)
),
question_badges as (
    select
        b.UserId,
        count(*) filter (where b.Class = 1) as gold_badges,
        count(*) filter (where b.Class = 2) as silver_badges,
        count(*) filter (where b.Class = 3) as bronze_badges,
        count(*) filter (where b.TagBased = 1) as tag_badges
    from Badges b
    group by b.UserId
),
monthly_activity as (
    select
        q.month_bucket,
        count(*) as questions_in_month,
        avg(q.Score) as avg_q_score_month,
        percentile_cont(0.9) within group (order by q.ViewCount) as p90_views
    from recent_questions q
    group by q.month_bucket
),
accepted_answer_latency as (
    select
        q.QuestionId,
        case when q.AcceptedAnswerId is not null then
            (select a.CreationDate from Posts a where a.Id = q.AcceptedAnswerId) - q.CreationDate
        end as accepted_latency
    from Posts q
    where q.PostTypeId = 1
      and q.CreationDate >= now() - interval '365 days'
),
leaderboard as (
    select
        q.OwnerUserId as UserId,
        count(*) as q_count,
        avg(q.Score) as avg_q_score,
        sum(coalesce(v.upvotes,0)) as sum_upvotes,
        sum(coalesce(v.downvotes,0)) as sum_downvotes,
        sum(coalesce(v.bounty_started,0)) as sum_bounty_started
    from recent_questions q
    left join vote_aggs v on v.PostId = q.QuestionId
    group by q.OwnerUserId
),
complex_predicate as (
    select
        q.QuestionId,
        (
            coalesce(v.upvotes,0) - coalesce(v.downvotes,0)
        ) * coalesce(a.answer_count,0)
        + least(coalesce(q.ViewCount,0), 10000)
        + case when ce.first_closed_at is null then 500 else -500 end
        + case when dl.dup_link_count > 0 then -200 else 0 end
        + coalesce(a.max_answer_score,0) * 10
        + case when cq.accepted_latency is not null and cq.accepted_latency < interval '2 days' then 300 else 0 end
    as complexity_score
    from recent_questions q
    left join vote_aggs v on v.PostId = q.QuestionId
    left join answer_stats a on a.QuestionId = q.QuestionId
    left join close_events ce on ce.PostId = q.QuestionId
    left join dup_links dl on dl.PostId = q.QuestionId
    left join accepted_answer_latency cq on cq.QuestionId = q.QuestionId
),
ranked_questions as (
    select
        q.QuestionId,
        q.CreationDate,
        q.OwnerUserId,
        q.Score,
        q.ViewCount,
        q.Title,
        q.Tags,
        oa.DisplayName as OwnerName,
        oa.Reputation as OwnerReputation,
        oa.LocationNorm,
        oa.has_github,
        qa.gold_badges,
        qa.silver_badges,
        qa.bronze_badges,
        qa.tag_badges,
        a.answer_count,
        a.answers_in_24h,
        a.first_answer_time,
        a.max_answer_score,
        v.upvotes,
        v.downvotes,
        v.bounty_started,
        v.bounty_awarded,
        c.comment_count,
        c.max_comment_score,
        ce.first_closed_at,
        ce.last_reopened_at,
        dl.dup_link_count,
        dl.linked_count,
        tl.tag,
        tl.tag_global_count,
        tl.tag_pop_rank,
        mp.questions_in_month,
        mp.avg_q_score_month,
        mp.p90_views,
        cp.complexity_score,
        row_number() over (
            partition by q.OwnerUserId
            order by cp.complexity_score desc nulls last, q.Score desc nulls last, q.ViewCount desc nulls last
        ) as rn_owner,
        row_number() over (
            order by cp.complexity_score desc nulls last, q.Score desc nulls last, q.ViewCount desc nulls last
        ) as rn_global
    from recent_questions q
    left join owner_dims oa on oa.UserId = q.OwnerUserId
    left join question_badges qa on qa.UserId = q.OwnerUserId
    left join answer_stats a on a.QuestionId = q.QuestionId
    left join vote_aggs v on v.PostId = q.QuestionId
    left join comment_aggs c on c.PostId = q.QuestionId
    left join close_events ce on ce.PostId = q.QuestionId
    left join dup_links dl on dl.PostId = q.QuestionId
    left join tag_quality tl on tl.QuestionId = q.QuestionId and tl.tag_pop_rank <= 3
    left join monthly_activity mp on mp.month_bucket = q.month_bucket
    left join complex_predicate cp on cp.QuestionId = q.QuestionId
),
top_users as (
    select
        ld.UserId,
        ld.q_count,
        ld.avg_q_score,
        ld.sum_upvotes,
        ld.sum_downvotes,
        dense_rank() over (order by ld.sum_upvotes - ld.sum_downvotes desc, ld.q_count desc) as user_rank
    from leaderboard ld
),
finalized as (
    select
        rq.*,
        tu.user_rank
    from ranked_questions rq
    left join top_users tu on tu.UserId = rq.OwnerUserId
    where
        (rq.rn_owner <= 5 or rq.rn_global <= 200)
        and (
            rq.Score >= 0
            or (rq.upvotes - rq.downvotes) >= -2
            or rq.first_closed_at is null
        )
        and (
            rq.tag is null
            or length(rq.tag) between 1 and 35
        )
        and coalesce(rq.Title, '') <> ''
)
select
    f.QuestionId,
    f.OwnerUserId,
    coalesce(f.OwnerName, concat('user#', f.OwnerUserId::text)) as OwnerName,
    f.OwnerReputation,
    f.user_rank,
    f.Score,
    f.ViewCount,
    f.upvotes,
    f.downvotes,
    f.bounty_started,
    f.bounty_awarded,
    f.answer_count,
    f.answers_in_24h,
    extract(epoch from (f.first_answer_time - f.CreationDate)) as secs_to_first_answer,
    extract(epoch from (now() - f.CreationDate)) as age_seconds,
    f.comment_count,
    f.max_comment_score,
    f.first_closed_at,
    f.last_reopened_at,
    f.dup_link_count,
    f.linked_count,
    f.tag,
    f.tag_global_count,
    f.tag_pop_rank,
    f.Title,
    coalesce(f.Tags, '[]') as TagsRaw,
    f.LocationNorm,
    f.has_github,
    f.gold_badges,
    f.silver_badges,
    f.bronze_badges,
    f.tag_badges,
    f.questions_in_month,
    f.avg_q_score_month,
    f.p90_views,
    f.complexity_score,
    f.rn_owner,
    f.rn_global
from finalized f
qualify row_number() over (partition by f.QuestionId order by f.tag_pop_rank nulls last) = 1
order by f.complexity_score desc nulls last, f.Score desc, f.ViewCount desc, f.QuestionId
limit 500;