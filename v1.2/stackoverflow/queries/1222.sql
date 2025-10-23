-- {"query": "1222.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.2, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1436} 
with RecursiveTagCounts as (
    select
        t.Id,
        t.TagName,
        t.Count,
        coalesce(p.AnswerCount,0) as AnswersCount,
        row_number() over (partition by t.TagName order by t.Count desc) as rn
    from Tags t
    left join Posts p on p.Id = t.ExcerptPostId and p.PostTypeId = 1
    where t.TagName is not null
),
UserReputations as (
    select 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        count(distinct b.Id) as BadgeCount,
        coalesce(sum(case when b.Class = 1 then 1 else 0 end), 0) as GoldBadges,
        coalesce(sum(case when b.Class = 2 then 1 else 0 end), 0) as SilverBadges,
        coalesce(sum(case when b.Class = 3 then 1 else 0 end), 0) as BronzeBadges,
        length(coalesce(u.AboutMe, '')) as AboutMeLength,
        greatest(u.UpVotes - u.DownVotes, 0) as EffectiveVotes
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.UpVotes, u.DownVotes, u.AboutMe
),
QuestionStats as (
    select
        p.Id,
        p.Title,
        p.CreationDate,
        p.Score,
        coalesce(p.ViewCount, 0) as Views,
        p.Tags,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        rank() over (partition by p.OwnerUserId order by p.Score desc) as QuestionRankByOwner
    from Posts p
    where p.PostTypeId = 1 and p.CreationDate > '2010-01-01'
),
FilteredAnswers as (
    select
        p.Id,
        p.ParentId,
        p.Score,
        p.CreationDate,
        p.OwnerUserId,
        p.Body,
        dense_rank() over (partition by p.ParentId order by p.Score desc, p.CreationDate) as AnswerRank
    from Posts p
    where p.PostTypeId = 2 and p.Score > 0
),
AnswerVotes as (
    select
        a.Id,
        count(v.Id) filter (where v.VoteTypeId = 2) as UpVotes,
        count(v.Id) filter (where v.VoteTypeId = 3) as DownVotes,
        max(v.CreationDate) as LastVoteDate
    from FilteredAnswers a
    left join Votes v on v.PostId = a.Id
    group by a.Id
),
PostCommentsAggregated as (
    select
        c.PostId,
        count(c.Id) as NumberOfComments,
        sum(case when c.Score > 0 then 1 else 0 end) as PositiveComments,
        sum(case when c.Score <= 0 then 1 else 0 end) as NonPositiveComments,
        max(c.CreationDate) as LastCommentDate
    from Comments c
    group by c.PostId
)
select 
    q.Id as QuestionId,
    q.Title,
    tc.TagName,
    tc.Count as TagUsageCount,
    ur.DisplayName as QuestionOwner,
    ur.Reputation as OwnerReputation,
    q.Score as QuestionScore,
    q.Views as QuestionViews,
    qa.AnswerCount,
    fa.Id as TopAnswerId,
    fa.Score as TopAnswerScore,
    av.UpVotes as TopAnswerUpVotes,
    av.DownVotes as TopAnswerDownVotes,
    pc.NumberOfComments as QuestionComments,
    pc2.NumberOfComments as TopAnswerComments,
    ts.Name as LatestPostHistoryType,
    lkt.Name as LatestLinkType,
    case when q.AcceptedAnswerId = fa.Id then 1 else 0 end as AcceptedAnswerIsTopAnswer,
    (
        select count(*)
        from Votes v2
        where v2.PostId = q.Id and v2.VoteTypeId = 2 and v2.CreationDate > cast('2024-10-01' as date) - interval '30 days'
    ) as RecentQuestionUpVotes,
    greatest(
        ((coalesce(fa.Score, 0) * 0.6) + (coalesce(av.UpVotes, 0) * 0.3) - (coalesce(av.DownVotes, 0) * 0.4) + (coalesce(pc2.NumberOfComments, 0)*0.1)),
        0
    ) as CalculatedAnswerScore,
    -- correlated subquery in select
    (
        select max(pht.CreationDate)
        from PostHistory pht
        where pht.PostId = q.Id
    ) as LatestPostHistoryDate,
    concat(
        substring(q.Title from 1 for 20),
        case when length(q.Title) > 20 then '...' else '' end,
        ' [Tags: ',
        coalesce(q.Tags, 'none'),
        ']'
    ) as ShortTitleAndTags
from QuestionStats q
left join Tags tc on tc.TagName = any(string_to_array(replace(replace(q.Tags, '<', ''), '>', ','), ','))
left join UserReputations ur on ur.Id = q.OwnerUserId
left join LATERAL (
    select count(*) as AnswerCount from Posts pa where pa.ParentId = q.Id and pa.PostTypeId = 2
) qa on true
left join LATERAL (
    select fa.*
    from FilteredAnswers fa
    where fa.ParentId = q.Id and fa.AnswerRank = 1
    limit 1
) fa on true
left join AnswerVotes av on av.Id = fa.Id
left join PostCommentsAggregated pc on pc.PostId = q.Id
left join PostCommentsAggregated pc2 on pc2.PostId = fa.Id
left join LATERAL (
    select pht2.PostHistoryTypeId, pht2.CreationDate
    from PostHistory pht2
    where pht2.PostId = q.Id
    order by pht2.CreationDate desc nulls last limit 1
) ph on true
left join PostHistoryTypes ts on ts.Id = ph.PostHistoryTypeId
left join LATERAL (
    select pl.LinkTypeId
    from PostLinks pl
    where pl.PostId = q.Id
    order by pl.CreationDate desc nulls last limit 1
) plk on true
left join LinkTypes lkt on lkt.Id = plk.LinkTypeId
where ur.Reputation > 1000
order by q.Score desc, qa.AnswerCount desc
limit 50;