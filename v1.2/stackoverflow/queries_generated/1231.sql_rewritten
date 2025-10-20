-- {"query": "1231.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.2, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1271} 
with UserBadgeCounts as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges,
        count(distinct p.Id) as TotalPosts,
        sum(p.Score) as TotalPostScore
    from Users u
    left join Badges b on b.UserId = u.Id
    left join Posts p on p.OwnerUserId = u.Id
    where u.Reputation > 1000 or u.Reputation is null
    group by u.Id, u.DisplayName
),
TopPostsForUsers AS (
    select
        p.Id,
        p.OwnerUserId,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Title,
        dense_rank() over (partition by p.OwnerUserId order by p.Score desc nulls last, p.ViewCount desc nulls last) as PostRank
    from Posts p
    where p.Score is not null
),
HighestScoringAnswerPerQuestion as (
    select distinct on (p.ParentId)
        p.ParentId as QuestionId,
        p.Id as AnswerId,
        p.Score as AnswerScore,
        u.DisplayName as AnswerOwner
    from Posts p
    join Users u on u.Id = p.OwnerUserId
    where p.PostTypeId = 2 and p.Score is not null
    order by p.ParentId, p.Score desc nulls last
),
UserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct ph.Id) as EditsMade,
        count(distinct (
            select 1 from Comments c where c.UserId = u.Id and c.CreationDate >= cast('2024-10-01' as date) - interval '30 days'
        )) as RecentComments,
        max(ph.CreationDate) as LastEditDate,
        max(c.CreationDate) as LastCommentDate
    from Users u
    left join PostHistory ph on ph.UserId = u.Id
    left join Comments c on c.UserId = u.Id
    group by u.Id, u.DisplayName
),
QuestionsClosedRecently AS (
    select 
        ph.PostId,
        ph.CreationDate,
        cr.Name as CloseReason
    from PostHistory ph
    join CloseReasonTypes cr on cr.Id = cast(ph.Comment as int)
    where ph.PostHistoryTypeId = 10 -- Post Closed
      and ph.CreationDate >= cast('2024-10-01' as date) - interval '60 days'
),
DuplicateQuestionPairs as (
    select
        pl.PostId as DuplicatePostId,
        pl.RelatedPostId as OriginalPostId,
        p1.Title as DuplicateTitle,
        p2.Title as OriginalTitle
    from PostLinks pl
    join Posts p1 on p1.Id = pl.PostId
    join Posts p2 on p2.Id = pl.RelatedPostId
    where pl.LinkTypeId = 3 -- Duplicate
),
UserReputationBracket as (
    select 
        u.Id as UserId,
        u.DisplayName,
        case 
            when u.Reputation >= 100000 then '100k+'
            when u.Reputation >= 50000 then '50k-99,999'
            when u.Reputation >= 20000 then '20k-49,999'
            when u.Reputation >= 10000 then '10k-19,999'
            else '<10k'
        end as ReputationRange
    from Users u
)
select
    ubc.UserId,
    ubc.DisplayName,
    ur.ReputationRange,
    ubc.GoldBadges,
    ubc.SilverBadges,
    ubc.BronzeBadges,
    ubc.TotalPosts,
    ubc.TotalPostScore,
    ua.EditsMade,
    ua.RecentComments,
    ua.LastEditDate,
    ua.LastCommentDate,
    tp.PostRank,
    tp.Title as TopPostTitle,
    coalesce(hsa.AnswerId, null) as HighestScoringAnswerId,
    coalesce(hsa.AnswerScore, 0) as HighestAnswerScore,
    coalesce(hsa.AnswerOwner, 'N/A') as HighestAnswerOwner,
    qc.PostId as RecentlyClosedQuestionId,
    qc.CloseReason as RecentCloseReason,
    dup.DuplicatePostId,
    dup.OriginalPostId,
    dup.DuplicateTitle,
    dup.OriginalTitle,
    case 
        when ubc.GoldBadges > 0 then concat('Gold:', ubc.GoldBadges)
        when ubc.SilverBadges > 0 then concat('Silver:', ubc.SilverBadges)
        when ubc.BronzeBadges > 0 then concat('Bronze:', ubc.BronzeBadges)
        else 'No Badges'
    end as BadgeSummary
from UserBadgeCounts ubc
join UserActivity ua on ua.UserId = ubc.UserId
join UserReputationBracket ur on ur.UserId = ubc.UserId
left join TopPostsForUsers tp on tp.OwnerUserId = ubc.UserId and tp.PostRank = 1
left join HighestScoringAnswerPerQuestion hsa on hsa.QuestionId = tp.Id
left join lateral (
    select *
    from QuestionsClosedRecently qc
    where qc.PostId = tp.Id
    order by qc.CreationDate desc
    limit 1
) qc on true
left join lateral (
    select *
    from DuplicateQuestionPairs dup
    where dup.DuplicatePostId = tp.Id OR dup.OriginalPostId = tp.Id
    order by dup.DuplicatePostId, dup.OriginalPostId
    limit 1
) dup on true
where ubc.TotalPosts > 10
order by ubc.GoldBadges desc nulls last, ubc.TotalPostScore desc nulls last
limit 100;