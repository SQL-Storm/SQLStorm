with RecursiveUserBadges as (
    select u.Id as UserId, u.DisplayName, b.Name as BadgeName, b.Class, b.Date,
        row_number() over (partition by u.Id order by b.Date desc) as rn
    from Users u
    left join Badges b on u.Id = b.UserId
    where b.Class in (1, 2, 3)
),
RecentPostsWithAnswers as (
    select p.Id, p.PostTypeId, p.Title, p.CreationDate, p.Score, p.ViewCount, p.Tags,
        (select count(*) from Posts a where a.ParentId = p.Id) as AnswerCount,
        (select avg(score) from Posts a where a.ParentId = p.Id) as AvgAnswerScore,
        p.OwnerUserId
    from Posts p
    where p.PostTypeId = 1 and p.CreationDate > cast('2024-10-01 12:34:56' as timestamp) - interval '1 year'
),
PostsWithVotes as (
    select p.Id, p.PostTypeId, p.Title, p.CreationDate, p.Score, p.ViewCount, p.Tags,
        coalesce(sum(case when v.VoteTypeId = 2 then 1 else 0 end), 0) as UpVotes,
        coalesce(sum(case when v.VoteTypeId = 3 then 1 else 0 end), 0) as DownVotes,
        coalesce(sum(case when v.VoteTypeId = 8 then v.BountyAmount else 0 end), 0) as BountySum,
        p.OwnerUserId
    from Posts p
    left join Votes v on p.Id = v.PostId
    where p.PostTypeId in (1, 2)
    group by p.Id, p.PostTypeId, p.Title, p.CreationDate, p.Score, p.ViewCount, p.Tags, p.OwnerUserId
),
UserActivity as (
    select u.Id as UserId, u.DisplayName, count(distinct p.Id) as PostCount,
        count(distinct c.Id) as CommentCount,
        count(distinct ph.Id) as EditCount,
        max(u.LastAccessDate) as LastSeen,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join PostHistory ph on ph.UserId = u.Id
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
),
PostLinksWithTypes as (
    select pl.Id, pl.PostId, pl.RelatedPostId, lt.Name as LinkTypeName, pl.CreationDate
    from PostLinks pl
    join LinkTypes lt on pl.LinkTypeId = lt.Id
),
QuestionsWithDuplicates as (
    select p.Id as QuestionId, p.Title, count(pl.Id) as DuplicateCount
    from Posts p
    left join PostLinksWithTypes pl on p.Id = pl.PostId and pl.LinkTypeName = 'Duplicate'
    where p.PostTypeId = 1
    group by p.Id, p.Title
),
RankedAnswers as (
    select a.Id, a.ParentId as QuestionId, a.Score,
        row_number() over (partition by a.ParentId order by a.Score desc, a.CreationDate asc) as AnswerRank
    from Posts a
    where a.PostTypeId = 2
),
TopAnswersWithUser as (
    select ra.Id as AnswerId, ra.QuestionId, ra.Score, ra.AnswerRank,
        u.Id as UserId, u.DisplayName, u.Reputation,
        ua.GoldBadges, ua.SilverBadges, ua.BronzeBadges
    from RankedAnswers ra
    left join Users u on ra.Id = u.Id
    left join UserActivity ua on ua.UserId = u.Id
    where ra.AnswerRank <= 3
),
TagUsage as (
    select tag.TagName, count(*) as UsageCount
    from Posts p,
         lateral (
           select regexp_split_to_table(substring(p.Tags from 2 for length(p.Tags) - 2), '><') as TagName
         ) as tag
    where p.PostTypeId = 1 and p.Tags is not null
    group by tag.TagName
),
PopularTags as (
    select TagName, UsageCount,
        rank() over (order by UsageCount desc) as UsageRank
    from TagUsage
),
PostsWithCloseReasons as (
    select p.Id, p.Title, ph.Comment as CloseReasonId, crt.Name as CloseReasonName, ph.CreationDate as CloseDate
    from Posts p
    left join PostHistory ph on p.Id = ph.PostId and ph.PostHistoryTypeId = 10
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as smallint)
    where ph.PostHistoryTypeId = 10
),
CombinedQuestions as (
    select rp.Id, rp.Title, rp.CreationDate, rp.Score, rp.ViewCount, rp.Tags,
        coalesce(qd.DuplicateCount,0) as DuplicateCount,
        coalesce(pc.CloseReasonName, 'Open') as CloseReason,
        rp.AnswerCount, rp.AvgAnswerScore,
        pwv.UpVotes, pwv.DownVotes, pwv.BountySum
    from RecentPostsWithAnswers rp
    left join QuestionsWithDuplicates qd on rp.Id = qd.QuestionId
    left join PostsWithVotes pwv on rp.Id = pwv.Id
    left join PostsWithCloseReasons pc on rp.Id = pc.Id
)
select cq.Id as QuestionId, cq.Title, cq.CreationDate, cq.Score, cq.ViewCount, cq.Tags,
    cq.AnswerCount, cq.AvgAnswerScore, cq.DuplicateCount, cq.CloseReason,
    cq.UpVotes, cq.DownVotes, cq.BountySum,
    pt.TagName as PopularTag, pt.UsageCount as PopularTagUsage,
    ta.AnswerId, ta.Score as AnswerScore, ta.AnswerRank,
    ta.UserId as AnswerUserId, ta.DisplayName as AnswerUserName, ta.Reputation as AnswerUserReputation,
    ta.GoldBadges, ta.SilverBadges, ta.BronzeBadges
from CombinedQuestions cq
left join lateral (
    select pt.TagName, pt.UsageCount
    from PopularTags pt,
         lateral (
           select regexp_split_to_table(substring(cq.Tags from 2 for length(cq.Tags) - 2), '><') as TagName
         ) as t
    where pt.TagName = t.TagName
    limit 1
) pt on true
left join TopAnswersWithUser ta on ta.QuestionId = cq.Id
where cq.Score > 5 and (cq.CloseReason = 'Open' or cq.CloseReason is null)
group by cq.Id, cq.Title, cq.CreationDate, cq.Score, cq.ViewCount, cq.Tags,
    cq.AnswerCount, cq.AvgAnswerScore, cq.DuplicateCount, cq.CloseReason,
    cq.UpVotes, cq.DownVotes, cq.BountySum,
    pt.TagName, pt.UsageCount,
    ta.AnswerId, ta.Score, ta.AnswerRank,
    ta.UserId, ta.DisplayName, ta.Reputation,
    ta.GoldBadges, ta.SilverBadges, ta.BronzeBadges
order by cq.Score desc, cq.ViewCount desc, ta.AnswerRank asc
limit 100;