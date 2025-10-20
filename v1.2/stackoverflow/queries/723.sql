-- {"query": "723.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.7, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1153} 
with RecursiveUserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        u.Location,
        coalesce(u.AboutMe, '') as AboutMe,
        count(p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        count(b.Id) as BadgeCount,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as TotalUpVotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as TotalDownVotes,
        row_number() over (partition by u.Location order by u.Reputation desc) as RankByLocation
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Badges b on b.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Location, u.AboutMe
),
TopUsers as (
    select *
    from RecursiveUserActivity
    where RankByLocation <= 3
),
QuestionAnswerStats as (
    select
        q.Id as QuestionId,
        q.Title,
        q.CreationDate as QuestionCreation,
        q.Score as QuestionScore,
        q.ViewCount,
        q.Tags,
        count(a.Id) as AnswersCount,
        max(a.Score) as MaxAnswerScore,
        avg(a.Score) as AvgAnswerScore,
        sum(case when a.OwnerUserId = q.OwnerUserId then 1 else 0 end) as SelfAnswerCount
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
    group by q.Id, q.Title, q.CreationDate, q.Score, q.ViewCount, q.Tags
),
RecentComments as (
    select
        c.PostId,
        c.UserId,
        c.CreationDate,
        c.Text,
        row_number() over (partition by c.PostId order by c.CreationDate desc) as CommentRank
    from Comments c
),
PostLinkDuplicates as (
    select
        pl.PostId,
        pl.RelatedPostId,
        lt.Name as LinkTypeName,
        p1.Title as PostTitle,
        p2.Title as RelatedPostTitle
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    join Posts p1 on p1.Id = pl.PostId
    join Posts p2 on p2.Id = pl.RelatedPostId
    where lt.Name = 'Duplicate'
),
UserBadgeRanks as (
    select
        b.UserId,
        b.Name as BadgeName,
        b.Class,
        dense_rank() over (partition by b.UserId order by b.Class) as BadgeRank
    from Badges b
),
UserReputationChanges as (
    select
        ph.UserId,
        ph.PostId,
        ph.PostHistoryTypeId,
        ph.CreationDate,
        sum(case when ph.PostHistoryTypeId in (1,4) then 5 else 0 end) -
        sum(case when ph.PostHistoryTypeId = 12 then 10 else 0 end) as RepDelta
    from PostHistory ph
    group by ph.UserId, ph.PostId, ph.PostHistoryTypeId, ph.CreationDate
),
UserAggregateRep as (
    select
        urc.UserId,
        sum(RepDelta) as TotalRepDelta
    from UserReputationChanges urc
    group by urc.UserId
)
select
    tu.UserId,
    tu.DisplayName,
    tu.Reputation,
    tu.Location,
    tu.QuestionCount,
    tu.AnswerCount,
    tu.BadgeCount,
    tu.TotalUpVotes,
    tu.TotalDownVotes,
    tas.QuestionId,
    tas.Title as QuestionTitle,
    tas.QuestionCreation,
    tas.QuestionScore,
    tas.ViewCount,
    tas.AnswersCount,
    tas.MaxAnswerScore,
    tas.AvgAnswerScore,
    tas.SelfAnswerCount,
    rc.Text as LatestComment,
    rc.CreationDate as LatestCommentDate,
    pld.RelatedPostId as DuplicateOfPostId,
    pld.RelatedPostTitle as DuplicateOfPostTitle,
    ubr.BadgeName as TopBadgeName,
    ubr.Class as TopBadgeClass,
    coalesce(uar.TotalRepDelta, 0) as CalculatedRepDelta
from TopUsers tu
left join QuestionAnswerStats tas on tas.QuestionId = (
    select p.Id
    from Posts p
    where p.OwnerUserId = tu.UserId and p.PostTypeId = 1
    order by p.Score desc nulls last
    limit 1
)
left join RecentComments rc on rc.PostId = tas.QuestionId and rc.CommentRank = 1
left join PostLinkDuplicates pld on pld.PostId = tas.QuestionId
left join UserBadgeRanks ubr on ubr.UserId = tu.UserId and ubr.BadgeRank = 1
left join UserAggregateRep uar on uar.UserId = tu.UserId
where tu.Location is not null and tu.Location <> ''
order by tu.Location, tu.Reputation desc;