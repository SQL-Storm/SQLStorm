with RecentQuestions as (
    select 
        p.Id,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        u.DisplayName as OwnerName,
        u.Reputation,
        coalesce(p.AcceptedAnswerId, -1) as AcceptedAnswerId,
        p.OwnerUserId
    from Posts p
    left join Users u on p.OwnerUserId = u.Id
    where p.PostTypeId = 1
      and p.CreationDate > cast('2024-10-01' as date) - interval '30' day
),
AnswersWithVotes as (
    select 
        a.Id,
        a.ParentId,
        a.Score as AnswerScore,
        count(v.Id) filter (where v.VoteTypeId = 2) as UpVotes,
        count(v.Id) filter (where v.VoteTypeId = 3) as DownVotes,
        sum(case when v.VoteTypeId = 8 then v.BountyAmount else 0 end) as TotalBounty
    from Posts a
    left join Votes v on a.Id = v.PostId
    where a.PostTypeId = 2
    group by a.Id, a.ParentId, a.Score
),
TopAnswerRanks as (
    select
        a.ParentId as QuestionId,
        a.Id as AnswerId,
        a.AnswerScore,
        a.UpVotes,
        a.DownVotes,
        a.TotalBounty,
        row_number() over (partition by a.ParentId order by a.AnswerScore desc, a.UpVotes desc, a.DownVotes asc) as Rank
    from AnswersWithVotes a
),
QuestionBadges as (
    select
        b.UserId,
        array_agg(distinct b.Name) as BadgeList,
        count(*) as BadgeCount,
        max(b.Class) as MaxBadgeClass
    from Badges b
    join Posts p on p.OwnerUserId = b.UserId
    where p.PostTypeId = 1
      and p.CreationDate > cast('2024-10-01' as date) - interval '90' day
    group by b.UserId
),
PostLinkCounts as (
    select
        pl.PostId,
        count(distinct pl.RelatedPostId) filter (where pl.LinkTypeId = 1) as LinkedCount,
        count(distinct pl.RelatedPostId) filter (where pl.LinkTypeId = 3) as DuplicateCount
    from PostLinks pl
    group by pl.PostId
),
ClosedQuestions as (
    select
        ph.PostId,
        crt.Name as CloseReason,
        ph.CreationDate as CloseDate
    from PostHistory ph
    join PostHistoryTypes pht on ph.PostHistoryTypeId = pht.Id and pht.Name = 'Post Closed'
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as integer) -- CloseReasonId stored in Comment for type 10
),
QuestionActivity as (
    select
        p.Id,
        greatest(
            coalesce(p.LastActivityDate, timestamp '1900-01-01'),
            coalesce(max(c.CreationDate), timestamp '1900-01-01'),
            coalesce(max(ph.CreationDate), timestamp '1900-01-01')
        ) as LastRelevantActivity
    from Posts p
    left join Comments c on c.PostId = p.Id
    left join PostHistory ph on ph.PostId = p.Id
    where p.PostTypeId = 1
    group by p.Id, p.LastActivityDate
)

select
    rq.Id as QuestionId,
    rq.Title,
    rq.CreationDate as QuestionCreation,
    rq.Score as QuestionScore,
    rq.ViewCount,
    rq.Tags,
    rq.OwnerName,
    rq.Reputation as OwnerReputation,
    coalesce(pb.BadgeCount, 0) as OwnerBadgeCount,
    coalesce(array_to_string(pb.BadgeList, ', '), 'None') as OwnerBadges,
    coalesce(pb.MaxBadgeClass, 0) as OwnerMaxBadgeClass,
    pl.LinkedCount,
    pl.DuplicateCount,
    coalesce(cq.CloseReason, 'Open') as CloseStatus,
    cq.CloseDate,
    qa.AnswerId as TopAnswerId,
    qa.AnswerScore as TopAnswerScore,
    qa.UpVotes as TopAnswerUpVotes,
    qa.DownVotes as TopAnswerDownVotes,
    qa.TotalBounty as TopAnswerTotalBounty,
    qa.Rank as TopAnswerRank,
    qa.AnswerScore * 1.0 / nullif(rq.Score,0) as AnswerToQuestionScoreRatio,
    qa.UpVotes - qa.DownVotes as NetAnswerVotes,
    qa.AnswerScore + coalesce(qa.TotalBounty,0) as AnswerScoreWithBounty,
    (qa.AnswerId is not null) as HasAnswers,
    (qa.AnswerScore is not null) as HasValidAnswerScore,
    (qa.AnswerId = rq.AcceptedAnswerId) as IsAcceptedAnswer,
    qa.AnswerScore - rq.Score as ScoreDifference,
    qa.AnswerScore - avg(qa.AnswerScore) over () as AnswerScoreVsAverage,
    qa.Rank,
    qa.AnswerScore * 
        case 
            when lower(rq.Tags) like '%sql%' then 1.5 
            when lower(rq.Tags) like '%performance%' then 1.3 
            else 1.0 
        end as WeightedAnswerScore,
    qa.AnswerScore + row_number() over (order by qa.AnswerScore desc) as AnswerScorePlusRank,
    ra.LastRelevantActivity
from RecentQuestions rq
left join TopAnswerRanks qa on qa.QuestionId = rq.Id and qa.Rank = 1
left join QuestionBadges pb on pb.UserId = rq.OwnerUserId
left join PostLinkCounts pl on pl.PostId = rq.Id
left join ClosedQuestions cq on cq.PostId = rq.Id
left join QuestionActivity ra on ra.Id = rq.Id
where
    (qa.AnswerScore is null or qa.AnswerScore > 0)
    and (
        lower(rq.Tags) like '%sql%'
        or lower(rq.Tags) like '%index%'
        or lower(rq.Tags) like '%performance%'
        or lower(rq.Title) like '%join%'
        or exists (
            select 1 from Comments c where c.PostId = rq.Id and lower(c.Text) like '%optimization%'
        )
    )
group by
    rq.Id,
    rq.Title,
    rq.CreationDate,
    rq.Score,
    rq.ViewCount,
    rq.Tags,
    rq.OwnerName,
    rq.Reputation,
    rq.AcceptedAnswerId,
    rq.OwnerUserId,
    pl.LinkedCount,
    pl.DuplicateCount,
    cq.CloseReason,
    cq.CloseDate,
    qa.AnswerId,
    qa.AnswerScore,
    qa.UpVotes,
    qa.DownVotes,
    qa.TotalBounty,
    qa.Rank,
    pb.BadgeCount,
    pb.BadgeList,
    pb.MaxBadgeClass,
    ra.LastRelevantActivity
order by 
    WeightedAnswerScore desc nulls last,
    rq.CreationDate desc
limit 100;