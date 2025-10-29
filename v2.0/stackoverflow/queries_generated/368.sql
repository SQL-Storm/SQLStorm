-- {"query": "368.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3264} 
with recent_posts as (
    select
        p.Id as PostId,
        p.PostTypeId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.Tags,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        p.LastActivityDate,
        coalesce(p.OwnerDisplayName, u.DisplayName) as OwnerName,
        u.Reputation,
        u.Location
    from Posts p
    left join Users u on u.Id = p.OwnerUserId
    where p.CreationDate >= (select max(CreationDate) - interval '365 days' from Posts)
),
tag_expanded as (
    select
        rp.*,
        unnest(string_to_array(substring(rp.Tags from 2 for length(rp.Tags)-2), '><')) as tag
    from recent_posts rp
    where rp.PostTypeId = 1
      and rp.Tags is not null
      and rp.Tags like '<%>'
),
tag_stats as (
    select
        te.tag,
        count(*) as tag_q_count,
        sum(case when te.Score > 0 then 1 else 0 end) as tag_q_pos,
        avg(te.Score::numeric) as tag_q_avg_score,
        avg(nullif(te.ViewCount,0)) as tag_q_avg_views
    from tag_expanded te
    group by te.tag
),
answers as (
    select
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.OwnerUserId as AnswerUserId,
        a.Score as AnswerScore,
        a.CreationDate as AnswerCreationDate
    from Posts a
    where a.PostTypeId = 2
      and a.CreationDate >= (select max(CreationDate) - interval '365 days' from Posts)
),
answerer_stats as (
    select
        ans.AnswerUserId,
        count(*) as a_count,
        sum(case when ans.AnswerScore > 0 then 1 else 0 end) as a_pos_count,
        avg(ans.AnswerScore::numeric) as a_avg_score,
        min(ans.AnswerCreationDate) as first_answer_date,
        max(ans.AnswerCreationDate) as last_answer_date
    from answers ans
    where ans.AnswerUserId is not null
    group by ans.AnswerUserId
),
votes_last_year as (
    select
        v.PostId,
        v.VoteTypeId,
        count(*) as v_count,
        sum(coalesce(v.BountyAmount,0)) as bounty_sum
    from Votes v
    where v.CreationDate >= (select max(CreationDate) - interval '365 days' from Votes)
    group by v.PostId, v.VoteTypeId
),
vote_pivot as (
    select
        p.Id as PostId,
        coalesce(max(case when v.VoteTypeId = 2 then v.v_count end),0) as upvotes,
        coalesce(max(case when v.VoteTypeId = 3 then v.v_count end),0) as downvotes,
        coalesce(max(case when v.VoteTypeId = 5 then v.v_count end),0) as favorites,
        coalesce(max(case when v.VoteTypeId = 8 then v.bounty_sum end),0) as bounty_started,
        coalesce(max(case when v.VoteTypeId = 9 then v.bounty_sum end),0) as bounty_awarded
    from Posts p
    left join votes_last_year v on v.PostId = p.Id
    where p.CreationDate >= (select max(CreationDate) - interval '365 days' from Posts)
    group by p.Id
),
postlink_dupes as (
    select
        pl.PostId,
        count(*) filter (where pl.LinkTypeId = 3) as dup_count,
        count(*) filter (where pl.LinkTypeId = 1) as link_count
    from PostLinks pl
    where pl.CreationDate >= (select max(CreationDate) - interval '365 days' from PostLinks)
    group by pl.PostId
),
post_closes as (
    select
        ph.PostId,
        max(case when ph.PostHistoryTypeId = 10 then ph.CreationDate end) as closed_at,
        max(case when ph.PostHistoryTypeId = 11 then ph.CreationDate end) as reopened_at,
        max(case when ph.PostHistoryTypeId = 10 then ph.Comment end) as close_reason_id_raw
    from PostHistory ph
    where ph.PostHistoryTypeId in (10,11)
      and ph.CreationDate >= (select max(CreationDate) - interval '365 days' from PostHistory)
    group by ph.PostId
),
normalized_close_reason as (
    select
        pc.PostId,
        case
            when pc.close_reason_id_raw ~ '^[0-9]+$' then cast(pc.close_reason_id_raw as int)
            else null
        end as CloseReasonId,
        pc.closed_at,
        pc.reopened_at
    from post_closes pc
),
close_reason_names as (
    select
        ncr.PostId,
        cr.Name as CloseReasonName,
        ncr.closed_at,
        ncr.reopened_at
    from normalized_close_reason ncr
    left join CloseReasonTypes cr on cr.Id = ncr.CloseReasonId
),
owner_activity as (
    select
        rp.OwnerUserId,
        count(*) as owner_post_count,
        sum(rp.Score) as owner_post_score_sum,
        avg(rp.Score::numeric) as owner_post_score_avg,
        max(rp.LastActivityDate) as owner_last_activity
    from recent_posts rp
    where rp.OwnerUserId is not null
    group by rp.OwnerUserId
),
user_badges as (
    select
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as gold_count,
        sum(case when b.Class = 2 then 1 else 0 end) as silver_count,
        sum(case when b.Class = 3 then 1 else 0 end) as bronze_count,
        sum(case when b.TagBased = 1 then 1 else 0 end) as tag_badge_count,
        min(b.Date) as first_badge_date,
        max(b.Date) as last_badge_date
    from Badges b
    group by b.UserId
),
question_answer_join as (
    select
        te.PostId as QuestionId,
        te.tag,
        a.AnswerId,
        a.AnswerUserId,
        a.AnswerScore
    from tag_expanded te
    left join answers a on a.QuestionId = te.PostId
),
qa_agg as (
    select
        qaj.QuestionId,
        count(distinct qaj.AnswerId) as answers_total,
        count(distinct qaj.AnswerUserId) as unique_answerers,
        avg(qaj.AnswerScore::numeric) filter (where qaj.AnswerId is not null) as avg_answer_score,
        string_agg(distinct qaj.tag, ',' order by qaj.tag) as tags_csv
    from question_answer_join qaj
    group by qaj.QuestionId
),
user_quality as (
    select
        u.Id as UserId,
        u.Reputation,
        u.UpVotes,
        u.DownVotes,
        (u.UpVotes - u.DownVotes) as vote_delta,
        case when u.DownVotes = 0 then null else (u.UpVotes::numeric / nullif(u.DownVotes,0)) end as up_down_ratio,
        ub.gold_count, ub.silver_count, ub.bronze_count, ub.tag_badge_count,
        oa.owner_post_count, oa.owner_post_score_sum, oa.owner_post_score_avg,
        oa.owner_last_activity,
        as2.a_count, as2.a_pos_count, as2.a_avg_score
    from Users u
    left join user_badges ub on ub.UserId = u.Id
    left join owner_activity oa on oa.OwnerUserId = u.Id
    left join answerer_stats as2 on as2.AnswerUserId = u.Id
),
ranked_questions as (
    select
        rp.PostId,
        rp.Title,
        rp.OwnerUserId,
        rp.OwnerName,
        rp.Reputation,
        rp.ViewCount,
        rp.Score,
        qs.answers_total,
        qs.unique_answerers,
        qs.avg_answer_score,
        qs.tags_csv,
        vp.upvotes,
        vp.downvotes,
        vp.favorites,
        vp.bounty_started,
        vp.bounty_awarded,
        coalesce(pl.dup_count,0) as dup_count,
        coalesce(pl.link_count,0) as link_count,
        crn.CloseReasonName,
        rp.CreationDate,
        rp.LastActivityDate,
        row_number() over (
            partition by coalesce(rp.OwnerUserId, -1)
            order by rp.Score desc, rp.ViewCount desc, rp.CreationDate desc
        ) as rn_owner_top,
        dense_rank() over (
            order by (coalesce(vp.upvotes,0) - coalesce(vp.downvotes,0)) desc, rp.ViewCount desc
        ) as dr_netvotes
    from recent_posts rp
    left join qa_agg qs on qs.QuestionId = rp.PostId
    left join vote_pivot vp on vp.PostId = rp.PostId
    left join postlink_dupes pl on pl.PostId = rp.PostId
    left join close_reason_names crn on crn.PostId = rp.PostId
    where rp.PostTypeId = 1
),
topk as (
    select *
    from ranked_questions
    where rn_owner_top <= 3
),
owner_enriched as (
    select
        t.*,
        uq.vote_delta as owner_vote_delta,
        uq.up_down_ratio as owner_up_down_ratio,
        uq.gold_count, uq.silver_count, uq.bronze_count, uq.tag_badge_count,
        uq.owner_post_count, uq.owner_post_score_avg,
        uq.a_count as owner_answer_count_last_year
    from topk t
    left join user_quality uq on uq.UserId = t.OwnerUserId
),
tag_density as (
    select
        te.tag,
        count(*) as q_count,
        sum(case when rp.Score >= 5 then 1 else 0 end) as hot_q_count,
        avg(rp.ViewCount::numeric) as avg_views
    from tag_expanded te
    join recent_posts rp on rp.PostId = te.PostId
    group by te.tag
),
tag_rank as (
    select
        ts.tag,
        ts.tag_q_count,
        ts.tag_q_pos,
        ts.tag_q_avg_score,
        ts.tag_q_avg_views,
        td.q_count,
        td.hot_q_count,
        dense_rank() over (order by ts.tag_q_count desc, ts.tag_q_avg_score desc) as pop_rank
    from tag_stats ts
    left join tag_density td on td.tag = ts.tag
),
question_tag_rank as (
    select
        te.PostId,
        min(tr.pop_rank) as best_tag_rank,
        max(tr.pop_rank) as worst_tag_rank,
        avg(tr.pop_rank::numeric) as avg_tag_rank
    from tag_expanded te
    join tag_rank tr on tr.tag = te.tag
    group by te.PostId
),
final as (
    select
        oe.PostId,
        oe.Title,
        oe.OwnerName,
        oe.Reputation as OwnerReputation,
        oe.Score,
        oe.ViewCount,
        oe.answers_total,
        oe.unique_answerers,
        oe.avg_answer_score,
        oe.tags_csv,
        oe.upvotes,
        oe.downvotes,
        oe.favorites,
        oe.bounty_started,
        oe.bounty_awarded,
        oe.dup_count,
        oe.link_count,
        coalesce(oe.CloseReasonName, 'N/A') as CloseReasonName,
        oe.CreationDate,
        oe.LastActivityDate,
        oe.dr_netvotes,
        oe.owner_vote_delta,
        oe.owner_up_down_ratio,
        oe.gold_count, oe.silver_count, oe.bronze_count, oe.tag_badge_count,
        oe.owner_post_count, oe.owner_post_score_avg,
        oe.owner_answer_count_last_year,
        qtr.best_tag_rank, qtr.worst_tag_rank, qtr.avg_tag_rank,
        case
            when coalesce(oe.upvotes,0) + coalesce(oe.downvotes,0) = 0 then null
            else (oe.upvotes::numeric - oe.downvotes::numeric) / nullif(oe.upvotes::numeric + oe.downvotes::numeric,0)
        end as vote_skew,
        case
            when oe.ViewCount is null or oe.ViewCount = 0 then null
            else oe.Score::numeric / nullif(oe.ViewCount,0)
        end as score_per_view,
        case
            when oe.answers_total is null or oe.answers_total = 0 then null
            else oe.favorites::numeric / nullif(oe.answers_total,0)
        end as favorites_per_answer,
        case
            when oe.bounty_started > 0 then 'HasBounty'
            when oe.dup_count > 0 then 'Duplicate'
            when oe.CloseReasonName is not null and oe.CloseReasonName <> 'N/A' then 'Closed'
            else 'Normal'
        end as status_bucket
    from owner_enriched oe
    left join question_tag_rank qtr on qtr.PostId = oe.PostId
),
dedup as (
    select
        f.*,
        row_number() over (
            partition by f.OwnerName, f.Title
            order by f.Score desc, f.ViewCount desc, f.PostId desc
        ) as rn
    from final f
)
select
    d.PostId,
    d.Title,
    d.OwnerName,
    d.OwnerReputation,
    d.Score,
    d.ViewCount,
    d.answers_total,
    d.unique_answerers,
    d.avg_answer_score,
    d.tags_csv,
    d.upvotes,
    d.downvotes,
    d.favorites,
    d.bounty_started,
    d.bounty_awarded,
    d.dup_count,
    d.link_count,
    d.CloseReasonName,
    d.CreationDate,
    d.LastActivityDate,
    d.dr_netvotes,
    d.owner_vote_delta,
    d.owner_up_down_ratio,
    d.gold_count, d.silver_count, d.bronze_count, d.tag_badge_count,
    d.owner_post_count, d.owner_post_score_avg,
    d.owner_answer_count_last_year,
    d.best_tag_rank, d.worst_tag_rank, d.avg_tag_rank,
    d.vote_skew,
    d.score_per_view,
    d.favorites_per_answer,
    d.status_bucket
from dedup d
where d.rn = 1
qualify
    (coalesce(d.upvotes,0) - coalesce(d.downvotes,0)) >= all (
        select (coalesce(vp2.upvotes,0) - coalesce(vp2.downvotes,0))
        from vote_pivot vp2
        where vp2.PostId = d.PostId
    )
order by d.dr_netvotes, d.Score desc, d.ViewCount desc, d.PostId desc
limit 500;