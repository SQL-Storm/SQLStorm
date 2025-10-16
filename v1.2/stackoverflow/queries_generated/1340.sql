-- {"query": "1340.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.3, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1499} 
with RecursiveUserBadges as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        b.Class,
        1 as BadgeCount
    from Users u
    left join Badges b on u.Id = b.UserId

    union all

    select
        rub.UserId,
        rub.DisplayName,
        rub.Reputation,
        rub.Class,
        rub.BadgeCount + 1
    from RecursiveUserBadges rub
    join Badges b2 on rub.UserId = b2.UserId
    where b2.Id > (select max(Id) from Badges where UserId = rub.UserId) 
        and rub.BadgeCount < 3
),
TopPostsWithRanks as (
    select
        p.Id,
        p.PostTypeId,
        p.AcceptedAnswerId,
        p.ParentId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        row_number() over (partition by p.PostTypeId order by p.Score desc, p.ViewCount desc NULLS LAST, p.CreationDate desc) as RankWithinType,
        dense_rank() over (order by p.CreationDate desc) as RecencyRank
    from Posts p
    where p.PostTypeId in (1,2) -- Questions and Answers
),
CteCombined as (
    select
        p.Id as PostId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        u.Id as OwnerUserId,
        u.DisplayName,
        u.Reputation,
        u.Location,
        u.Views as UserViews,
        u.UpVotes,
        u.DownVotes,
        pb1.BadgeCounts_Gold,
        pb1.BadgeCounts_Silver,
        pb1.BadgeCounts_Bronze,
        p.Title,
        p.Tags,
        ph_latest.Text as LatestEditComment,
        c.NumComments,
        case when p.AcceptedAnswerId is not null then 1 else 0 end as HasAcceptedAnswer,
        xp.LinkCount_Duplicate,
        xp.LinkCount_Linked
    from Posts p
    left join Users u on p.OwnerUserId = u.Id
    left join (
        select
            b.UserId,
            sum(case when b.Class = 1 then 1 else 0 end) as BadgeCounts_Gold,
            sum(case when b.Class = 2 then 1 else 0 end) as BadgeCounts_Silver,
            sum(case when b.Class = 3 then 1 else 0 end) as BadgeCounts_Bronze
        from Badges b
        group by b.UserId
    ) pb1 on u.Id = pb1.UserId
    left join (
        select ph.PostId, max(ph.Id) as MaxPHId
        from PostHistory ph
        where ph.PostHistoryTypeId in (4,5)
        group by ph.PostId
    ) phmax on phmax.PostId = p.Id
    left join PostHistory ph_latest on ph_latest.Id = phmax.MaxPHId
    left join (
        select PostId, count(*) as NumComments
        from Comments
        group by PostId
    ) c on p.Id = c.PostId
    left join (
        select
            pl.PostId,
            sum(case when pl.LinkTypeId = 3 then 1 else 0 end) as LinkCount_Duplicate,
            sum(case when pl.LinkTypeId = 1 then 1 else 0 end) as LinkCount_Linked
        from PostLinks pl
        group by pl.PostId
    ) xp on xp.PostId = p.Id
    where p.PostTypeId = 1
),
RankedAnswers as (
    select
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.Score,
        a.CreationDate,
        a.OwnerUserId,
        row_number() over (partition by a.ParentId order by a.Score desc nulls last, a.CreationDate asc) as AnswerRank
    from Posts a
    where a.PostTypeId = 2
),
HighScoreComments as (
    select
        c.PostId,
        string_agg(c.Text, ' ||| ' order by c.Score desc NULLS LAST, c.CreationDate asc) as TopComments
    from Comments c
    where c.Score > (select avg(Score) from Comments where Score is not null)
    group by c.PostId
),
UserLastActive as (
    select
        u.Id,
        u.DisplayName,
        u.LastAccessDate,
        dense_rank() over (order by u.LastAccessDate desc) as RecentAccessRank
    from Users u
)
select
    c.PostId,
    c.Title,
    c.Tags,
    c.Score as QuestionScore,
    c.ViewCount,
    c.CreationDate,
    c.DisplayName as QuestionOwnerName,
    c.Reputation as QuestionOwnerReputation,
    c.BadgeCounts_Gold,
    c.BadgeCounts_Silver,
    c.BadgeCounts_Bronze,
    c.HasAcceptedAnswer,
    c.NumComments as QuestionCommentCount,
    coalesce(rq_highest.Score, 0) as TopAnswerScore,
    coalesce(rq_highest.AnswerOwnerName, 'N/A') as TopAnswerOwner,
    coalesce(rq_highest.AnswerOwnerReputation, 0) as TopAnswerOwnerReputation,
    c.LatestEditComment,
    ua.LastAccessDate as QuestionOwnerLastAccess,
    csrf.TagsAreClean,
    hc.TopComments,
    fold.LinkedDuplicatesRatio,
    fold.LinkedDuplicatesScore
from CteCombined c
outer apply (
    select
        a.Score,
        u.DisplayName as AnswerOwnerName,
        u.Reputation as AnswerOwnerReputation
    from RankedAnswers a
    left join Users u on u.Id = a.OwnerUserId
    where a.QuestionId = c.PostId and a.AnswerRank = 1
    limit 1
) rq_highest
left join UserLastActive ua on ua.Id = c.OwnerUserId
left join HighScoreComments hc on hc.PostId = c.PostId
cross join lateral (
    select
        case
            when c.LinkCount_Duplicate + c.LinkCount_Linked = 0 then 0
            else (c.LinkCount_Duplicate::float / greatest(c.LinkCount_Duplicate + c.LinkCount_Linked,1))
        end as LinkedDuplicatesRatio,
        coalesce(c.LinkCount_Duplicate * c.ViewCount, 0) as LinkedDuplicatesScore
) fold
cross join lateral (
    select
        case when strpos(coalesce(c.Tags,''), '<sql>') > 0 or strpos(coalesce(c.Title,''), 'query') > 0 then false else true end as TagsAreClean
) csrf
where c.Score >= all (
    select score - 5 from Posts p3
    where p3.PostTypeId = 1 and p3.AcceptedAnswerId is not null
)
order by c.Score desc, TopAnswerScore desc, c.ViewCount desc
limit 50;