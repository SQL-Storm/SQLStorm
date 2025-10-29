with RecursiveUserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        p.Id as PostId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.FavoriteCount,
        coalesce(b.BadgeCount, 0) as BadgeCount,
        row_number() over (partition by u.Id order by p.CreationDate desc) as RecentPostRank,
        (
            select count(*) 
            from Comments c 
            where c.UserId = u.Id and c.CreationDate > u.CreationDate - interval '1 year'
        ) as CommentsLastYear,
        case when u.WebsiteUrl is null or length(trim(u.WebsiteUrl)) = 0 then 'NoWebsite' else 'HasWebsite' end as WebsiteStatus,
        -- replace PostgreSQL array functions with standard string processing: remove leading/trailing angle brackets and replace '><' with ',' then trim commas
        case
            when coalesce(p.Tags, '') = '' then ''
            else
                trim(both ',' from replace(replace(coalesce(p.Tags, ''), '><', ','), '<', ''))
        end as TagsCleaned,
        greatest(p.Score, 0) * coalesce(b.BadgeCount, 0) as WeightedScoreBadge
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join (
        select UserId, count(*) as BadgeCount
        from Badges
        where Date >= cast('2024-10-01' as date) - interval '365 day'
        group by UserId
    ) b on b.UserId = u.Id
    where u.Reputation > 1000
),
FilteredPosts as (
    select * from RecursiveUserActivity
    where PostTypeId in (1, 2) -- Questions and Answers
    and RecentPostRank <= 5
    and Score > 0
),
AggregatedStats as (
    select
        UserId,
        DisplayName,
        count(distinct PostId) as PostCount,
        sum(Score) as TotalScore,
        avg(ViewCount) as AvgViews,
        max(FavoriteCount) as MaxFavoriteCount,
        sum(CommentsLastYear) as TotalCommentsLastYear,
        sum(BadgeCount) as TotalBadges,
        string_agg(distinct TagsCleaned, ',') as AllTags,
        sum(WeightedScoreBadge) as WeightedScoreBadgeSum
    from FilteredPosts
    group by UserId, DisplayName
),
RankedUsers as (
    select
        UserId,
        DisplayName,
        PostCount,
        TotalScore,
        AvgViews,
        MaxFavoriteCount,
        TotalCommentsLastYear,
        TotalBadges,
        AllTags,
        WeightedScoreBadgeSum,
        dense_rank() over (order by WeightedScoreBadgeSum desc, TotalScore desc) as UserRank
    from AggregatedStats
),
DuplicateLinks as (
    select pl.PostId, pl.RelatedPostId, pl.CreationDate
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId and lt.Name = 'Duplicate'
),
UserCloseVotes as (
    select distinct ph.UserId, ph.PostId
    from PostHistory ph
    join PostHistoryTypes pht on pht.Id = ph.PostHistoryTypeId and pht.Name = 'Post Closed'
    where ph.UserId is not null
),
CloseVoteUsers as (
    select u.Id, u.DisplayName, count(distinct ucv.PostId) as CloseVotesCast
    from Users u
    left join UserCloseVotes ucv on ucv.UserId = u.Id
    group by u.Id, u.DisplayName
),
FinalReport as (
    select
        ru.UserId,
        ru.DisplayName,
        ru.PostCount,
        ru.TotalScore,
        ru.AvgViews,
        ru.MaxFavoriteCount,
        ru.TotalCommentsLastYear,
        ru.TotalBadges,
        ru.AllTags,
        ru.UserRank,
        coalesce(cvu.CloseVotesCast, 0) as CloseVotesCast,
        case when coalesce(cvu.CloseVotesCast, 0) > 10 then 'ActiveCloser' else 'InactiveCloser' end as CloseVoteActivity,
        substr(coalesce(ru.AllTags, ''), 1, 50) || case when length(coalesce(ru.AllTags, '')) > 50 then '...' else '' end as TagSummary
    from RankedUsers ru
    left join CloseVoteUsers cvu on cvu.Id = ru.UserId
    where ru.UserRank <= 50
),
PostsWithTopScorers as (
    select
        p.Id, p.Title, p.Score, p.ViewCount,
        fu.UserRank, fu.DisplayName as OwnerName,
        row_number() over (partition by fu.UserRank order by p.Score desc) as PostRankPerUser,
        (select count(*) from Comments c where c.PostId = p.Id and c.Score > 0) as PositiveCommentsCount,
        (select max(Score) from Posts where OwnerUserId = p.OwnerUserId and PostTypeId = 2) as MaxAnswerScoreByOwner
    from Posts p
    join FinalReport fu on fu.UserId = p.OwnerUserId
    where p.PostTypeId = 1 and p.Score > 5
)
select
    fr.UserRank, fr.DisplayName, fr.PostCount, fr.TotalScore, fr.AvgViews, fr.MaxFavoriteCount,
    fr.TotalCommentsLastYear, fr.TotalBadges, fr.CloseVotesCast, fr.CloseVoteActivity, fr.TagSummary,
    ptps.Title as TopQuestionTitle, ptps.Score as TopQuestionScore, ptps.ViewCount as TopQuestionViews,
    coalesce(ptps.PositiveCommentsCount, 0) as PositiveCommentsCount,
    coalesce(ptps.MaxAnswerScoreByOwner, 0) as MaxAnswerScoreByOwner
from FinalReport fr
left join PostsWithTopScorers ptps on ptps.UserRank = fr.UserRank and ptps.PostRankPerUser = 1
order by fr.UserRank;