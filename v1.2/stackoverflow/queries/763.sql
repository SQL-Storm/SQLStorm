with RecursiveTagCounts as (
    select
        t.Id as TagId,
        t.TagName,
        t.Count,
        coalesce(p.AnswerCount, 0) as TotalAnswers,
        row_number() over (partition by t.Id order by t.Count desc) as rn
    from Tags t
    left join Posts p on p.PostTypeId = 1 and p.Tags like concat('%<', t.TagName, '>%')
),
UserBadgeSummary as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct case when b.Class = 1 then b.Id end) as GoldBadges,
        count(distinct case when b.Class = 2 then b.Id end) as SilverBadges,
        count(distinct case when b.Class = 3 then b.Id end) as BronzeBadges,
        sum(case when b.TagBased = true then 1 else 0 end) as TagBasedBadges
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
),
LatestPostVotes as (
    select
        p.Id as PostId,
        p.OwnerUserId,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
        sum(case when v.VoteTypeId = 5 then 1 else 0 end) as FavoriteCountVotes
    from Posts p
    left join Votes v on v.PostId = p.Id
    group by p.Id, p.OwnerUserId, p.PostTypeId, p.CreationDate, p.Score, p.ViewCount
),
TopActiveUsers as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        count(p.Id) as PostCount,
        sum(p.Score) as TotalPostScore,
        row_number() over (order by count(p.Id) desc, sum(p.Score) desc) as ActivityRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation
    having count(p.Id) > 10
),
PostWithHistoryCount as (
    select
        p.Id as PostId,
        p.Title,
        p.PostTypeId,
        p.CreationDate,
        count(ph.Id) as HistoryCount,
        max(ph.CreationDate) as LastHistoryDate
    from Posts p
    left join PostHistory ph on ph.PostId = p.Id
    group by p.Id, p.Title, p.PostTypeId, p.CreationDate
),
DuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        lt.Name as LinkTypeName
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    where lt.Name = 'Duplicate'
),
UserCommentStats as (
    select
        c.UserId,
        count(c.Id) as CommentCount,
        avg(length(c.Text)) as AvgCommentLength,
        sum(case when c.CreationDate > cast(cast('2024-10-01 12:34:56' as timestamp) - interval '90 days' as timestamp) then 1 else 0 end) as RecentCommentCount
    from Comments c
    group by c.UserId
),
QuestionAnswerStats as (
    select
        q.Id as QuestionId,
        q.Title,
        count(a.Id) as AnswerCount,
        max(a.Score) as MaxAnswerScore,
        sum(case when a.Score > 5 then 1 else 0 end) as HighScoreAnswers,
        (select count(*) from Votes v where v.PostId = q.Id and v.VoteTypeId = 2) as QuestionUpVotes
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
    group by q.Id, q.Title
),
UserRankedBadges as (
    select
        b.UserId,
        b.Name,
        b.Class,
        row_number() over (partition by b.UserId order by b.Date desc) as BadgeRank
    from Badges b
),
UserLatestBadges as (
    select
        ur.UserId,
        string_agg(ur.Name || ' (' || case ur.Class when 1 then 'Gold' when 2 then 'Silver' else 'Bronze' end || ')', ', ') as LatestBadges
    from UserRankedBadges ur
    where ur.BadgeRank <= 3
    group by ur.UserId
)
select
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    coalesce(ubs.GoldBadges, 0) as GoldBadges,
    coalesce(ubs.SilverBadges, 0) as SilverBadges,
    coalesce(ubs.BronzeBadges, 0) as BronzeBadges,
    coalesce(ubs.TagBasedBadges, 0) as TagBasedBadges,
    coalesce(uc.CommentCount, 0) as TotalComments,
    coalesce(uc.RecentCommentCount, 0) as RecentCommentsLast90Days,
    cast(coalesce(uc.AvgCommentLength, 0) as numeric(10,2)) as AvgCommentLength,
    coalesce(ta.PostCount, 0) as TotalPosts,
    coalesce(ta.TotalPostScore, 0) as TotalPostScore,
    coalesce(ulb.LatestBadges, 'None') as LatestBadges,
    qs.QuestionId,
    qs.Title as QuestionTitle,
    qs.AnswerCount,
    qs.MaxAnswerScore,
    qs.HighScoreAnswers,
    qs.QuestionUpVotes,
    phc.HistoryCount,
    phc.LastHistoryDate,
    dt.LinkTypeName as DuplicateLinkType,
    rank() over (partition by case when coalesce(ubs.GoldBadges,0) > 0 then 1 else 0 end order by u.Reputation desc) as ReputationRankWithinGoldBadgeGroup
from Users u
left join UserBadgeSummary ubs on ubs.UserId = u.Id
left join UserCommentStats uc on uc.UserId = u.Id
left join TopActiveUsers ta on ta.Id = u.Id
left join UserLatestBadges ulb on ulb.UserId = u.Id
left join QuestionAnswerStats qs on qs.QuestionId = (
    select p.Id from Posts p where p.PostTypeId = 1 and p.OwnerUserId = u.Id order by p.Score desc limit 1
)
left join PostWithHistoryCount phc on phc.PostId = qs.QuestionId
left join DuplicateLinks dt on dt.PostId = qs.QuestionId
where u.Reputation > 1000
order by u.Reputation desc, ta.PostCount desc
limit 100;