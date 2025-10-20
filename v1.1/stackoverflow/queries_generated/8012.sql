-- {"query": "8012.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2530} 
with recent_questions as (
    select
        q.Id as QuestionId,
        q.Title,
        q.OwnerUserId,
        q.CreationDate,
        q.Score,
        q.ViewCount,
        q.Tags,
        q.AcceptedAnswerId,
        date_trunc('month', q.CreationDate) as q_month
    from Posts q
    where q.PostTypeId = 1
      and q.CreationDate >= now() - interval '24 months'
),
answers as (
    select
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.OwnerUserId as AnswerOwnerId,
        a.Score as AnswerScore,
        a.CreationDate as AnswerCreationDate
    from Posts a
    where a.PostTypeId = 2
),
first_answer as (
    select distinct on (a.QuestionId)
        a.QuestionId,
        a.AnswerId,
        a.AnswerOwnerId,
        a.AnswerScore,
        a.AnswerCreationDate
    from answers a
    order by a.QuestionId, a.AnswerCreationDate
),
vote_agg as (
    select
        v.PostId,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as upvotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as downvotes,
        sum(case when v.VoteTypeId = 5 then 1 else 0 end) as favorites,
        sum(case when v.VoteTypeId in (8,9) then coalesce(v.BountyAmount,0) else 0 end) as bounty_total,
        min(v.CreationDate) filter (where v.VoteTypeId = 2) as first_upvote_at
    from Votes v
    group by v.PostId
),
comment_stats as (
    select
        c.PostId,
        count(*) as comment_count,
        max(c.Score) as max_comment_score,
        min(c.CreationDate) as first_comment_at,
        count(*) filter (where c.Text ilike '%thanks%' or c.Text ilike '%thank you%') as thanks_comments
    from Comments c
    group by c.PostId
),
post_history_events as (
    select
        ph.PostId,
        sum(case when ph.PostHistoryTypeId in (4,5,6) then 1 else 0 end) as edits,
        max(ph.CreationDate) filter (where ph.PostHistoryTypeId in (10,11,12,13,14,15,19,20,35,36)) as last_mod_action_at,
        bool_or(ph.PostHistoryTypeId = 50) as community_bumped,
        max(case when ph.PostHistoryTypeId = 10 then try_cast(nullif(ph.Comment,'') as int) end) as last_close_reason_id
    from PostHistory ph
    group by ph.PostId
),
tag_unrolled as (
    select
        q.QuestionId,
        unnest(string_to_array(substring(q.Tags, 2, greatest(length(q.Tags)-2,0)), '><')) as tag
    from recent_questions q
    where q.Tags is not null and q.Tags like '<%>'
),
tag_rank as (
    select
        t.tag,
        count(*) as tag_q_count,
        dense_rank() over (order by count(*) desc, tag) as tag_pop_rank
    from tag_unrolled t
    group by t.tag
),
user_basics as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate as UserCreated,
        coalesce(nullif(trim(u.Location),''), 'Unknown') as NormLocation,
        u.UpVotes,
        u.DownVotes
    from Users u
),
badges_agg as (
    select
        b.UserId,
        count(*) as badges_total,
        count(*) filter (where b.Class = 1) as gold_badges,
        count(*) filter (where b.Class = 2) as silver_badges,
        count(*) filter (where b.Class = 3) as bronze_badges,
        count(*) filter (where b.TagBased = 1) as tag_badges
    from Badges b
    group by b.UserId
),
duplicates as (
    select
        pl.PostId as DuplicatePostId,
        count(*) filter (where pl.LinkTypeId = 3) as dup_links_to,
        count(*) filter (where pl.LinkTypeId = 1) as linked_to
    from PostLinks pl
    group by pl.PostId
),
accepted_answerer_rep as (
    select
        q.QuestionId,
        ua.Reputation as AcceptedAnswererRep
    from recent_questions q
    join Posts acc on acc.Id = q.AcceptedAnswerId
    left join Users ua on ua.Id = acc.OwnerUserId
),
question_quality as (
    select
        q.QuestionId,
        q.Title,
        q.OwnerUserId,
        q.CreationDate,
        q.Score,
        q.ViewCount,
        q.Tags,
        q.q_month,
        va.upvotes,
        va.downvotes,
        va.favorites,
        va.bounty_total,
        cs.comment_count,
        cs.max_comment_score,
        phe.edits,
        phe.community_bumped,
        phe.last_close_reason_id,
        coalesce(da.dup_links_to,0) as dup_links_to,
        coalesce(da.linked_to,0) as linked_to,
        fa.AnswerId as FirstAnswerId,
        fa.AnswerOwnerId as FirstAnswerOwnerId,
        fa.AnswerScore as FirstAnswerScore,
        fa.AnswerCreationDate,
        aa.AcceptedAnswererRep,
        -- calculated metrics
        (coalesce(va.upvotes,0) - coalesce(va.downvotes,0)) as net_votes,
        case when q.ViewCount > 0 then (coalesce(va.upvotes,0)::numeric / q.ViewCount) else 0 end as upvote_view_ratio,
        extract(epoch from (fa.AnswerCreationDate - q.CreationDate))/3600.0 as hours_to_first_answer,
        extract(epoch from (va.first_upvote_at - q.CreationDate))/3600.0 as hours_to_first_upvote
    from recent_questions q
    left join vote_agg va on va.PostId = q.QuestionId
    left join comment_stats cs on cs.PostId = q.QuestionId
    left join post_history_events phe on phe.PostId = q.QuestionId
    left join duplicates da on da.DuplicatePostId = q.QuestionId
    left join first_answer fa on fa.QuestionId = q.QuestionId
    left join accepted_answerer_rep aa on aa.QuestionId = q.QuestionId
),
ranked_by_month as (
    select
        qq.*,
        percentile_cont(0.5) within group (order by coalesce(qq.Score,0)) over (partition by qq.q_month) as p50_score_month,
        percentile_cont(0.9) within group (order by coalesce(qq.ViewCount,0)) over (partition by qq.q_month) as p90_views_month,
        row_number() over (partition by qq.q_month order by coalesce(qq.ViewCount,0) desc, coalesce(qq.Score,0) desc) as rn_views_month,
        dense_rank() over (order by coalesce(qq.bounty_total,0) desc, coalesce(qq.favorites,0) desc) as dr_bounty_global
    from question_quality qq
),
owner_enriched as (
    select
        r.*,
        ub.DisplayName as OwnerName,
        ub.Reputation as OwnerReputation,
        ub.NormLocation as OwnerLocation,
        coalesce(ba.badges_total,0) as OwnerBadges,
        coalesce(ba.gold_badges,0) as OwnerGold,
        coalesce(ba.silver_badges,0) as OwnerSilver,
        coalesce(ba.bronze_badges,0) as OwnerBronze
    from ranked_by_month r
    left join user_basics ub on ub.UserId = r.OwnerUserId
    left join badges_agg ba on ba.UserId = r.OwnerUserId
),
tag_cross as (
    select
        oe.QuestionId,
        string_agg(format('%s#%s', tu.tag, tr.tag_pop_rank), '|' order by tr.tag_pop_rank, tu.tag) as tags_with_rank,
        min(tr.tag_pop_rank) as best_tag_rank
    from owner_enriched oe
    left join tag_unrolled tu on tu.QuestionId = oe.QuestionId
    left join tag_rank tr on tr.tag = tu.tag
    group by oe.QuestionId
),
closed_reasons as (
    select
        crt.Id as CloseReasonId,
        crt.Name as CloseReasonName
    from CloseReasonTypes crt
),
final as (
    select
        oe.QuestionId,
        coalesce(nullif(oe.Title,''), '[no title]') as Title,
        oe.OwnerUserId,
        coalesce(oe.OwnerName, concat('user#', oe.OwnerUserId::text)) as OwnerName,
        oe.OwnerReputation,
        oe.OwnerLocation,
        oe.OwnerBadges,
        oe.OwnerGold,
        oe.OwnerSilver,
        oe.OwnerBronze,
        oe.CreationDate,
        oe.q_month,
        oe.Score,
        oe.ViewCount,
        oe.upvotes,
        oe.downvotes,
        oe.favorites,
        oe.bounty_total,
        oe.comment_count,
        oe.max_comment_score,
        oe.edits,
        oe.community_bumped,
        oe.dup_links_to,
        oe.linked_to,
        oe.FirstAnswerId,
        oe.FirstAnswerOwnerId,
        oe.FirstAnswerScore,
        oe.AnswerCreationDate,
        oe.AcceptedAnswererRep,
        oe.net_votes,
        oe.upvote_view_ratio,
        oe.hours_to_first_answer,
        oe.hours_to_first_upvote,
        oe.p50_score_month,
        oe.p90_views_month,
        oe.rn_views_month,
        oe.dr_bounty_global,
        tc.tags_with_rank,
        tc.best_tag_rank,
        coalesce(crt.CloseReasonName, case when oe.last_close_reason_id is not null then concat('UnknownReason#', oe.last_close_reason_id::text) end) as CloseReasonName
    from owner_enriched oe
    left join tag_cross tc on tc.QuestionId = oe.QuestionId
    left join closed_reasons crt on crt.CloseReasonId = oe.last_close_reason_id
)
select *
from final
where
    -- complicated predicates for benchmarking
    coalesce(net_votes, 0) >= -5
    and (favorites >= 3 or bounty_total > 0 or best_tag_rank <= 25)
    and (
        hours_to_first_answer is null
        or hours_to_first_answer between 0 and 168
        or (hours_to_first_upvote is not null and hours_to_first_upvote < 72)
    )
    and (
        OwnerReputation >= 100
        or (OwnerBadges >= 5 and OwnerGold >= 1)
        or (OwnerLocation not ilike '%unknown%')
    )
    and (
        (dup_links_to = 0 and linked_to >= 2)
        or (dup_links_to >= 1 and Score >= 0)
        or dup_links_to is null
    )
    and (
        (tags_with_rank is not null and position('|c#' in lower(replace(tags_with_rank, 'C#', 'c#'))) = 0)
        or tags_with_rank is null
    )
    and (community_bumped is distinct from true)
    and (CloseReasonName is null or CloseReasonName not ilike '%duplicate%')
order by
    dr_bounty_global asc nulls last,
    rn_views_month asc nulls last,
    net_votes desc nulls last,
    CreationDate desc
limit 500;