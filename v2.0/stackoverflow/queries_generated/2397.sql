-- {"query": "2397.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1950} 
with RecursiveTagHierarchy as (
    select t.Id, t.TagName, t.ExcerptPostId, t.WikiPostId, 1 as Level
    from Tags t
    where t.IsModeratorOnly = 0 and t.IsRequired = 0

    union all

    select t2.Id, t2.TagName, t2.ExcerptPostId, t2.WikiPostId, r.Level + 1
    from Tags t2
    join RecursiveTagHierarchy r on t2.Id > r.Id
    where t2.IsModeratorOnly = 0 and t2.IsRequired = 0 and r.Level < 3
), QuestionAnswerAggregates as (
    select
        q.Id as QuestionId,
        q.Title,
        q.CreationDate,
        q.OwnerUserId,
        count(a.Id) as TotalAnswers,
        max(a.Score) as MaxAnswerScore,
        avg(coalesce(a.Score, 0)) as AvgAnswerScore,
        count(distinct v.UserId) filter (where v.VoteTypeId = 2) as UpVotesCount,
        count(distinct c.Id) as CommentCountTotal,
        count(distinct pb.Id) filter (where pb.PostHistoryTypeId = 10) as CloseVotesCount
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    left join Votes v on v.PostId = q.Id and v.VoteTypeId = 2
    left join Comments c on c.PostId = q.Id
    left join PostHistory pb on pb.PostId = q.Id and pb.PostHistoryTypeId = 10
    where q.PostTypeId = 1
    group by q.Id, q.Title, q.CreationDate, q.OwnerUserId
), UserReputationStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate as UserCreation,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges,

        -- Window function for reputation ranking
        rank() over (order by u.Reputation desc) as ReputationRank,

        -- Window function for badge sum ranking
        rank() over (order by (count(b.Id) filter (where b.Class = 1) * 3 + count(b.Id) filter (where b.Class = 2) * 2 + count(b.Id) filter (where b.Class = 3)) desc) as BadgeRank

    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate
), PostsWithLinkInfo as (
    select
        p.Id as PostId,
        p.Title,
        p.OwnerUserId,
        p.PostTypeId,
        count(pl.Id) filter (where lt.Name = 'Duplicate') as NumDuplicateLinks,
        count(pl.Id) filter (where lt.Name = 'Linked') as NumLinkedPosts,
        count(pl.Id) as TotalLinks
    from Posts p
    left join PostLinks pl on pl.PostId = p.Id
    left join LinkTypes lt on lt.Id = pl.LinkTypeId
    group by p.Id, p.Title, p.OwnerUserId, p.PostTypeId
), LatestPostHistoryPerPost as (
    select distinct on (ph.PostId)
        ph.PostId,
        ph.Id as PostHistoryId,
        ph.PostHistoryTypeId,
        ph.CreationDate as HistoryDate,
        ph.UserId,
        ph.UserDisplayName,
        ph.Comment,
        ph.Text
    from PostHistory ph
    order by ph.PostId, ph.CreationDate desc
), ComplexFilteredPosts as (
    select 
        p.Id,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        (select count(*) from Comments c where c.PostId = p.Id and c.CreationDate > p.CreationDate - interval '30 days') as RecentCommentsCount,
        (select count(*) from Votes v where v.PostId = p.Id and v.VoteTypeId = 2 and v.CreationDate > p.CreationDate - interval '30 days') as RecentUpvotes,
        row_number() over (partition by p.OwnerUserId order by p.Score desc) as RnkByUserScore
    from Posts p
    where p.PostTypeId = 1
      and (p.Tags ilike '%<sql>%' or p.Tags ilike '%<database>%')
      and p.Score > 0
      and p.ViewCount > 1000
), UnifiedUserActivity as (
    select u.Id as UserId, u.DisplayName, 'Post' as ActivityType, p.CreationDate as ActivityDate
    from Users u
    join Posts p on p.OwnerUserId = u.Id
    where p.CreationDate > u.CreationDate + interval '30 days'

    union all

    select u.Id, u.DisplayName, 'Comment', c.CreationDate
    from Users u
    join Comments c on c.UserId = u.Id
    where c.CreationDate > u.CreationDate + interval '30 days'

    union all

    select u.Id, u.DisplayName, 'Badge', b.Date
    from Users u
    join Badges b on b.UserId = u.Id
    where b.Date > u.CreationDate + interval '30 days'
), UserActivityRanks as (
    select 
        ua.UserId,
        ua.DisplayName,
        ua.ActivityType,
        ua.ActivityDate,
        row_number() over (partition by ua.UserId, ua.ActivityType order by ua.ActivityDate) as ActivityRowNum
    from UnifiedUserActivity ua
), ActivityIntervals as (
    select
        UserId,
        ActivityType,
        avg(lead(ActivityDate) over (partition by UserId, ActivityType order by ActivityDate) - ActivityDate) as AvgInterval
    from UserActivityRanks
    group by UserId, ActivityType
), ConsolidatedUserStats as (
    select 
        urs.UserId,
        urs.DisplayName,
        urs.Reputation,
        urs.GoldBadges,
        urs.SilverBadges,
        urs.BronzeBadges,
        coalesce(ai_post.AvgInterval, interval '0') as AvgPostInterval,
        coalesce(ai_comment.AvgInterval, interval '0') as AvgCommentInterval,
        coalesce(ai_badge.AvgInterval, interval '0') as AvgBadgeInterval
    from UserReputationStats urs
    left join ActivityIntervals ai_post on ai_post.UserId = urs.UserId and ai_post.ActivityType = 'Post'
    left join ActivityIntervals ai_comment on ai_comment.UserId = urs.UserId and ai_comment.ActivityType = 'Comment'
    left join ActivityIntervals ai_badge on ai_badge.UserId = urs.UserId and ai_badge.ActivityType = 'Badge'
)
select 
    qqa.QuestionId,
    qqa.Title as QuestionTitle,
    concat_ws(' | ', 
        'Score: ' || qqa.Score,
        'Answers: ' || qqa.TotalAnswers,
        'Max Answer Score: ' || coalesce(qqa.MaxAnswerScore, 0),
        'Avg Answer Score: ' || round(qqa.AvgAnswerScore::numeric,2),
        'Comments: ' || qqa.CommentCountTotal,
        'Close Votes: ' || qqa.CloseVotesCount
    ) as QuestionStats,
    urs.DisplayName as OwnerDisplayName,
    urs.Reputation as OwnerReputation,
    urs.GoldBadges,
    urs.SilverBadges,
    urs.BronzeBadges,
    pwi.NumDuplicateLinks,
    pwi.NumLinkedPosts,
    lph.PostHistoryTypeId,
    lph.Comment as LastHistoryComment,
    case when cfp.RecentUpvotes is null then 0 else cfp.RecentUpvotes end as RecentUpvotesLast30Days,
    cfp.RecentCommentsCount,
    cu.AvgPostInterval,
    cu.AvgCommentInterval,
    cu.AvgBadgeInterval
from QuestionAnswerAggregates qqa
join PostsWithLinkInfo pwi on pwi.PostId = qqa.QuestionId
left join LatestPostHistoryPerPost lph on lph.PostId = qqa.QuestionId
left join ComplexFilteredPosts cfp on cfp.Id = qqa.QuestionId
left join ConsolidatedUserStats cu on cu.UserId = qqa.OwnerUserId
left join UserReputationStats urs on urs.UserId = qqa.OwnerUserId
where
    (pwi.NumDuplicateLinks > 0 or lph.PostHistoryTypeId = 10)
    and qqa.TotalAnswers > 2
    and (cu.GoldBadges + cu.SilverBadges + cu.BronzeBadges) > 5
order by qqa.TotalAnswers desc, cu.Reputation desc
limit 50;