-- {"query": "2569.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1755} 
with RecursiveUserActivity as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        p.Id as PostId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.Title,
        ph.PostHistoryTypeId,
        ph.CreationDate as HistoryDate,
        ph.Comment as HistoryComment,
        row_number() over (partition by u.Id order by ph.CreationDate desc) as rn
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join PostHistory ph on ph.PostId = p.Id
    where u.Reputation > 1000
),
TopUserActivities as (
    select * from RecursiveUserActivity where rn <= 5
),
PostScoreRanks as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        rank() over (partition by p.PostTypeId order by p.Score desc nulls last) as ScoreRank,
        dense_rank() over (partition by p.OwnerUserId order by p.Score desc nulls last) as UserScoreRank
    from Posts p
    where p.Score is not null
),
TagsExploded as (
    select
        p.Id as PostId,
        unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags) - 2), '><')) as Tag
    from Posts p
    where p.Tags is not null and p.PostTypeId = 1
),
UserBadgeCounts as (
    select 
        b.UserId,
        b.Class,
        count(*) as BadgeCount
    from Badges b
    where b.TagBased = 0
    group by b.UserId, b.Class
),
UserTotalBadges as (
    select
        UserId,
        sum(BadgeCount) over (partition by UserId) as TotalBadges,
        sum(case when Class = 1 then BadgeCount else 0 end) as GoldBadges,
        sum(case when Class = 2 then BadgeCount else 0 end) as SilverBadges,
        sum(case when Class = 3 then BadgeCount else 0 end) as BronzeBadges
    from UserBadgeCounts
    group by UserId
),
UserTopTags as (
    select
        ub.UserId,
        te.Tag,
        count(*) as TagCount,
        rank() over (partition by ub.UserId order by count(*) desc) as RankByUser
    from Badges ub
    inner join TagsExploded te on te.PostId = (
        select p.Id from Posts p where p.OwnerUserId = ub.UserId limit 1
    )
    where ub.TagBased = 1
    group by ub.UserId, te.Tag
),
DuplicatePostLinks as (
    select pl.PostId, pl.RelatedPostId
    from PostLinks pl
    inner join LinkTypes lt on lt.Id = pl.LinkTypeId
    where lt.Name = 'Duplicate'
),
QuestionsWithDuplicateCount as (
    select 
        p.Id,
        p.Title,
        p.OwnerUserId,
        count(distinct dpl.RelatedPostId) as DuplicateCount
    from Posts p
    left join DuplicatePostLinks dpl on dpl.PostId = p.Id
    where p.PostTypeId = 1
    group by p.Id, p.Title, p.OwnerUserId
),
FilteredQuestions as (
    select 
        q.Id,
        q.Title,
        q.OwnerUserId,
        q.DuplicateCount,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        p.CreationDate
    from QuestionsWithDuplicateCount q
    inner join Posts p on p.Id = q.Id
    where q.DuplicateCount > 0 and p.Score >= 5 and p.AnswerCount > 2
),
QuestionRankWindow as (
    select *,
        row_number() over (partition by OwnerUserId order by Score desc, ViewCount desc) as UserQuestionRank
    from FilteredQuestions
),
CloseReasonsSummary as (
    select
        cht.Id,
        cht.Name as CloseReasonName,
        count(ph.Id) as CloseCount
    from CloseReasonTypes cht
    left join PostHistory ph on ph.PostHistoryTypeId = 10 and ph.Comment::int = cht.Id
    group by cht.Id, cht.Name
),
RecentActiveUsers as (
    select distinct UserId
    from Posts
    where LastActivityDate > current_date - interval '30 days' and OwnerUserId is not null
),
ActivitySummaryPerUser as (
    select
        u.Id as UserId,
        coalesce(count(distinct p.Id),0) as TotalPosts,
        coalesce(count(distinct c.Id),0) as TotalComments,
        coalesce(count(distinct v.Id),0) as TotalVotesGiven,
        coalesce(sum(v.BountyAmount),0) as TotalBountyGiven
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    group by u.Id
),
CorrelatedLatestPostComment as (
    select
        p.Id,
        p.OwnerUserId,
        (select c.Text from Comments c where c.PostId = p.Id order by c.CreationDate desc limit 1) as LatestCommentText
    from Posts p
    where p.PostTypeId = 1
)
select 
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    coalesce(ut.TotalBadges, 0) as TotalBadges,
    coalesce(ut.GoldBadges, 0) as GoldBadges,
    coalesce(ut.SilverBadges, 0) as SilverBadges,
    coalesce(ut.BronzeBadges, 0) as BronzeBadges,
    qs.Id as QuestionId,
    qs.Title as QuestionTitle,
    qs.Score as QuestionScore,
    qs.ViewCount as QuestionViews,
    qs.AnswerCount,
    qs.FavoriteCount,
    qs.DuplicateCount,
    qrw.UserQuestionRank,
    ph.PostHistoryTypeId,
    ph.Comment as PostHistoryComment,
    ph.CreationDate as PostHistoryDate,
    crs.CloseReasonName,
    crs.CloseCount,
    auc.TotalPosts,
    auc.TotalComments,
    auc.TotalVotesGiven,
    auc.TotalBountyGiven,
    latestcom.LatestCommentText,
    case 
        when u.WebsiteUrl is not null then substring(u.WebsiteUrl from 'https?://(?:www\.)?([^/]+)')
        else 'No Website'
    end as WebsiteDomain,
    coalesce(tu.Tag, 'NoTag') as TopTag,
    tu.TagCount,
    turr.ReputationDifference,
    case 
        when u.Location is null then 'Unknown location'
        else u.Location
    end as UserLocation
from Users u
left join UserTotalBadges ut on ut.UserId = u.Id
left join QuestionRankWindow qrw on qrw.OwnerUserId = u.Id and qrw.UserQuestionRank = 1
left join FilteredQuestions qs on qs.Id = qrw.Id
left join PostHistory ph on ph.PostId = qs.Id and ph.PostHistoryTypeId in (10,11)
left join CloseReasonsSummary crs on crs.CloseReasonName = ph.Comment
left join ActivitySummaryPerUser auc on auc.UserId = u.Id
left join CorrelatedLatestPostComment latestcom on latestcom.Id = qs.Id
left join UserTopTags tu on tu.UserId = u.Id and tu.RankByUser = 1
left join (
    select u1.Id, (u1.Reputation - u2.Reputation) as ReputationDifference
    from Users u1
    join Users u2 on u2.Id = u1.Id
    where u1.CreationDate > u2.CreationDate
) turr on turr.Id = u.Id
where u.Reputation > 1000 and (latestcom.LatestCommentText is not null or qs.AnswerCount > 0)
order by u.Reputation desc, qs.Score desc
limit 100;