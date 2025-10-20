with RecursiveUserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        coalesce(u.WebsiteUrl, 'N/A') as WebsiteUrl,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        row_number() over (partition by u.Id order by u.CreationDate) as ActivityRank,
        (
            select count(*) from Posts p where p.OwnerUserId = u.Id and p.PostTypeId = 1
        ) as QuestionCount,
        (
            select count(*) from Posts p where p.OwnerUserId = u.Id and p.PostTypeId = 2
        ) as AnswerCount,
        (
            select count(*) from Comments c where c.UserId = u.Id
        ) as CommentCount,
        (
            select count(*) from Badges b where b.UserId = u.Id and b.Class = 1
        ) as GoldBadges,
        (
            select count(*) from Badges b where b.UserId = u.Id and b.Class = 2
        ) as SilverBadges,
        (
            select count(*) from Badges b where b.UserId = u.Id and b.Class = 3
        ) as BronzeBadges
    from Users u
), LatestPostEdits as (
    select
        ph.PostId,
        max(ph.CreationDate) as LastEditDate
    from PostHistory ph
    where ph.PostHistoryTypeId in (4,5,6,7,8,9)
    group by ph.PostId
), PostDetails as (
    select
        p.Id,
        p.PostTypeId,
        pt.Name as PostTypeName,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        u.DisplayName as OwnerDisplayName,
        p.Title,
        p.Tags,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        lpe.LastEditDate,
        row_number() over (partition by p.OwnerUserId order by p.Score desc, p.ViewCount desc) as UserTopPostRank,
        coalesce(p.AcceptedAnswerId, -1) as AcceptedAnswerId
    from Posts p
    left join Users u on u.Id = p.OwnerUserId
    left join LatestPostEdits lpe on lpe.PostId = p.Id
    left join PostTypes pt on pt.Id = p.PostTypeId
    where p.PostTypeId in (1, 2)
), DuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        pl.CreationDate,
        pl.LinkTypeId,
        lt.Name as LinkTypeName
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    where pl.LinkTypeId = 3
), UserBadgeSummary as (
    select
        b.UserId,
        count(case when b.Class = 1 then 1 end) as GoldBadgeCount,
        count(case when b.Class = 2 then 1 end) as SilverBadgeCount,
        count(case when b.Class = 3 then 1 end) as BronzeBadgeCount,
        count(distinct b.Name) as DistinctBadges
    from Badges b
    group by b.UserId
), QuestionAnswerStats as (
    select
        q.Id as QuestionId,
        q.Title,
        q.Tags,
        q.Score as QuestionScore,
        q.ViewCount as QuestionViews,
        q.OwnerUserId as QuestionOwner,
        a.Id as AnswerId,
        a.Score as AnswerScore,
        a.OwnerUserId as AnswerOwner,
        a.CreationDate as AnswerCreationDate,
        row_number() over (partition by q.Id order by a.Score desc, a.CreationDate asc) as AnswerRank
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    join PostTypes ptq on ptq.Id = q.PostTypeId and ptq.Name = 'Question'
    where q.PostTypeId = 1
), TagExplode as (
    select
        q.Id as QuestionId,
        trim(both ' ' from regexp_split_to_table(
            substring(q.Tags from 2 for length(q.Tags) - 2),
            '><'
        )) as Tag
    from Posts q
    where q.PostTypeId = 1 and q.Tags is not null
), TagStats as (
    select
        t.Tag,
        count(distinct q.QuestionId) as QuestionCount,
        avg(q.QuestionScore) as AvgQuestionScore,
        max(q.QuestionScore) as MaxQuestionScore,
        count(distinct a.AnswerId) as AnswerCount,
        avg(a.AnswerScore) as AvgAnswerScore
    from TagExplode t
    left join QuestionAnswerStats q on q.QuestionId = t.QuestionId
    left join QuestionAnswerStats a on a.QuestionId = t.QuestionId and a.AnswerRank = 1
    group by t.Tag
), UserActivityRanked as (
    select
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.CreationDate,
        ua.Location,
        ua.WebsiteUrl,
        ua.Views,
        ua.UpVotes,
        ua.DownVotes,
        ua.ActivityRank,
        ua.QuestionCount,
        ua.AnswerCount,
        ua.CommentCount,
        ua.GoldBadges,
        ua.SilverBadges,
        ua.BronzeBadges,
        rank() over (order by ua.Reputation desc, ua.QuestionCount desc, ua.AnswerCount desc) as ReputationRank
    from RecursiveUserActivity ua
), ComplexUserSummary as (
    select
        uar.UserId,
        uar.DisplayName,
        uar.Reputation,
        uar.Location,
        uar.WebsiteUrl,
        uar.Views,
        uar.UpVotes,
        uar.DownVotes,
        uar.QuestionCount,
        uar.AnswerCount,
        uar.CommentCount,
        uar.GoldBadges,
        uar.SilverBadges,
        uar.BronzeBadges,
        ubs.GoldBadgeCount,
        ubs.SilverBadgeCount,
        ubs.BronzeBadgeCount,
        ubs.DistinctBadges,
        uar.ReputationRank,
        case 
            when uar.Reputation > 100000 then 'Legendary'
            when uar.Reputation > 50000 then 'Expert'
            when uar.Reputation > 10000 then 'Proficient'
            else 'Novice'
        end as ReputationLevel,
        coalesce(uar.Location, 'Unknown') || ' - ' || coalesce(uar.WebsiteUrl, 'No Website') as LocationWebsite,
        (uar.UpVotes - uar.DownVotes) as NetVotes,
        (uar.QuestionCount + uar.AnswerCount + uar.CommentCount) as TotalContributions,
        uar.CreationDate
    from UserActivityRanked uar
    left join UserBadgeSummary ubs on ubs.UserId = uar.UserId
)
select
    cus.UserId,
    cus.DisplayName,
    cus.Reputation,
    cus.ReputationLevel,
    cus.LocationWebsite,
    cus.Views,
    cus.NetVotes,
    cus.TotalContributions,
    cus.GoldBadges as BadgeGoldFromBadges,
    cus.SilverBadges as BadgeSilverFromBadges,
    cus.BronzeBadges as BadgeBronzeFromBadges,
    cus.GoldBadgeCount as BadgeGoldFromSummary,
    cus.SilverBadgeCount as BadgeSilverFromSummary,
    cus.BronzeBadgeCount as BadgeBronzeFromSummary,
    cus.DistinctBadges,
    (
        select count(*) from Posts p where p.OwnerUserId = cus.UserId and p.PostTypeId = 1 and p.ClosedDate is not null
    ) as ClosedQuestions,
    (
        select count(*) from DuplicateLinks dl join Posts p on p.Id = dl.PostId where p.OwnerUserId = cus.UserId
    ) as DuplicatePostsLinked,
    (
        select avg(ts.AvgQuestionScore) from TagStats ts where ts.Tag in (
            select regexp_split_to_table(substring(p.Tags from 2 for length(p.Tags) - 2), '><')
            from Posts p where p.OwnerUserId = cus.UserId and p.PostTypeId = 1 limit 10
        )
    ) as AvgTagQuestionScore,
    (
        select count(distinct ph.PostId)
        from PostHistory ph
        where ph.UserId = cus.UserId and ph.PostHistoryTypeId in (4,5,6) and ph.CreationDate > cus.CreationDate
    ) as EditsAfterJoinDate,
    (
        select string_agg(distinct lt.Name, ', ') 
        from PostLinks pl
        join LinkTypes lt on lt.Id = pl.LinkTypeId
        join Posts p on p.Id = pl.PostId
        where p.OwnerUserId = cus.UserId and pl.CreationDate > cast('2024-10-01 12:34:56' as timestamp) - interval '1 year'
    ) as RecentLinkTypes,
    (
        select count(*) from Comments c where c.UserId = cus.UserId and lower(c.Text) like '%sql%'
    ) as CommentsMentioningSQL,
    (
        select sum(v.BountyAmount) from Votes v where v.UserId = cus.UserId and v.BountyAmount is not null
    ) as TotalBountyGiven
from ComplexUserSummary cus
where cus.Reputation > 10000
order by cus.Reputation desc, cus.TotalContributions desc
limit 100;