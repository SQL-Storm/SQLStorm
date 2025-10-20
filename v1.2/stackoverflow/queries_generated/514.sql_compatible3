with RecursiveTagCounts as (
    select
        t.Id,
        t.TagName,
        t.Count,
        coalesce(p.AnswerCount, 0) as AnswerCount,
        coalesce(p.FavoriteCount, 0) as FavoriteCount,
        row_number() over (order by t.Count desc, t.TagName) as Rank
    from Tags t
    left join Posts p on p.Tags like '%' || '<' || t.TagName || '>' || '%' and p.PostTypeId = 1
    where t.IsModeratorOnly = false
),
UserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct case when p.PostTypeId = 1 then p.Id end) as QuestionsAsked,
        count(distinct case when p.PostTypeId = 2 then p.Id end) as AnswersGiven,
        count(distinct c.Id) as CommentsMade,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotesReceived,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotesReceived,
        max(case when p.PostTypeId = 2 then p.Score end) as MaxAnswerScore,
        max(case when p.PostTypeId = 1 then p.Score end) as MaxQuestionScore,
        case when max(case when p.PostTypeId = 2 then p.Score end) is null then 0 else 1 end as HasHighScoringAnswer
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Votes v on v.PostId = p.Id
    group by u.Id, u.DisplayName
),
CloseReasonCounts as (
    select
        cht.Name as CloseReason,
        count(*) as CloseCount
    from PostHistory ph
    join PostHistoryTypes chtt on ph.PostHistoryTypeId = chtt.Id
    join CloseReasonTypes cht on cast(ph.Comment as integer) = cht.Id
    where ph.PostHistoryTypeId = 10 and ph.Comment is not null and ph.Comment ~ '^\d+$'
    group by cht.Name
),
PostLinkDuplicates as (
    select
        pl.PostId,
        count(case when lt.Name = 'Duplicate' then 1 end) as DuplicateCount,
        count(distinct pl.RelatedPostId) as RelatedPostsCount
    from PostLinks pl
    join LinkTypes lt on pl.LinkTypeId = lt.Id
    group by pl.PostId
),
UserBadgeSummary as (
    select
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        count(*) as TotalBadges
    from Badges b
    group by b.UserId
),
TopPostsWithActivity as (
    select
        p.Id,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.FavoriteCount,
        p.Tags,
        u.DisplayName as OwnerName,
        row_number() over (partition by p.PostTypeId order by p.Score desc) as ScoreRank,
        lead(p.Score) over (partition by p.PostTypeId order by p.Score desc) as NextHigherScore,
        lag(p.Score) over (partition by p.PostTypeId order by p.Score desc) as PrevLowerScore,
        case when p.ClosedDate is not null then 1 else 0 end as IsClosed,
        coalesce(pld.DuplicateCount, 0) as DuplicateLinks,
        coalesce(pld.RelatedPostsCount, 0) as RelatedPosts,
        (select count(*) from Comments c where c.PostId = p.Id) as CommentCount,
        (select count(*) from Votes v where v.PostId = p.Id and v.VoteTypeId = 2) as UpVotes,
        (select count(*) from Votes v where v.PostId = p.Id and v.VoteTypeId = 3) as DownVotes
    from Posts p
    left join Users u on u.Id = p.OwnerUserId
    left join PostLinkDuplicates pld on pld.PostId = p.Id
    where p.PostTypeId in (1, 2)
),
CorrelatedUserStats as (
    select
        p.Id as PostId,
        (select count(*) from Posts p2 where p2.OwnerUserId = p.OwnerUserId and p2.PostTypeId = p.PostTypeId and p2.Score > p.Score) as HigherScorePostsByUser,
        (select max(p3.Score) from Posts p3 where p3.OwnerUserId = p.OwnerUserId and p3.PostTypeId = p.PostTypeId) as MaxScoreByUser,
        (select count(distinct c.UserId) from Comments c where c.PostId = p.Id and c.UserId is not null) as UniqueCommenters
    from Posts p
    where p.PostTypeId in (1, 2)
),
FinalSelection as (
    select
        t.Id as TagId,
        t.TagName,
        t.Count as TagUsageCount,
        t.AnswerCount,
        t.FavoriteCount,
        ua.UserId,
        ua.DisplayName as UserName,
        ua.QuestionsAsked,
        ua.AnswersGiven,
        ua.CommentsMade,
        ua.UpVotesReceived,
        ua.DownVotesReceived,
        ua.MaxAnswerScore,
        ua.MaxQuestionScore,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeBadges,
        p.Id as PostId,
        p.Title as PostTitle,
        p.Score as PostScore,
        p.ViewCount,
        p.FavoriteCount as PostFavoriteCount,
        p.IsClosed,
        p.DuplicateLinks,
        p.RelatedPosts,
        p.CommentCount,
        p.UpVotes,
        p.DownVotes,
        cus.HigherScorePostsByUser,
        cus.MaxScoreByUser,
        cus.UniqueCommenters,
        crc.CloseReason,
        crc.CloseCount
    from RecursiveTagCounts t
    join UserActivity ua on ua.UserId in (
        select OwnerUserId from Posts where Tags like '%' || '<' || t.TagName || '>' || '%' limit 5
    )
    left join UserBadgeSummary ub on ub.UserId = ua.UserId
    left join TopPostsWithActivity p on p.OwnerName = ua.DisplayName and p.Tags like '%' || '<' || t.TagName || '>' || '%'
    left join CorrelatedUserStats cus on cus.PostId = p.Id
    left join CloseReasonCounts crc on crc.CloseReason is not null
    where t.Rank <= 10
)
select
    TagId,
    TagName,
    TagUsageCount,
    AnswerCount,
    FavoriteCount,
    UserId,
    UserName,
    QuestionsAsked,
    AnswersGiven,
    CommentsMade,
    UpVotesReceived,
    DownVotesReceived,
    MaxAnswerScore,
    MaxQuestionScore,
    GoldBadges,
    SilverBadges,
    BronzeBadges,
    PostId,
    PostTitle,
    PostScore,
    ViewCount,
    PostFavoriteCount,
    IsClosed,
    DuplicateLinks,
    RelatedPosts,
    CommentCount,
    UpVotes,
    DownVotes,
    HigherScorePostsByUser,
    MaxScoreByUser,
    UniqueCommenters,
    CloseReason,
    CloseCount
from FinalSelection
order by TagUsageCount desc, UserName, PostScore desc
limit 100;