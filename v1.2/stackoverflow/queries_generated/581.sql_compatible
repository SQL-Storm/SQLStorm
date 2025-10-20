with RecursiveTagStats as (
    select
        t.Id as TagId,
        t.TagName,
        coalesce(p.AnswerCount, 0) as AnswerCount,
        coalesce(p.ViewCount, 0) as ViewCount,
        coalesce(p.Score, 0) as Score,
        coalesce(p.FavoriteCount, 0) as FavoriteCount,
        row_number() over (order by coalesce(p.ViewCount,0) desc) as RankByViews
    from Tags t
    left join Posts p on p.Id = t.ExcerptPostId and p.PostTypeId = 1
),
UserBadgeCounts as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges,
        row_number() over (order by u.Reputation desc) as UserRank
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation
),
TopQuestions as (
    select
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        (select count(*) from Comments c where c.PostId = p.Id) as CommentCount,
        (select count(*) from Votes v where v.PostId = p.Id and v.VoteTypeId = 2) as UpVotes,
        (select count(*) from Votes v where v.PostId = p.Id and v.VoteTypeId = 3) as DownVotes,
        row_number() over (partition by p.OwnerUserId order by p.Score desc) as RankByScorePerUser
    from Posts p
    where p.PostTypeId = 1 and p.ClosedDate is null
),
UserActivitySummary as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) as TotalPosts,
        count(distinct ph.Id) filter (where ph.PostHistoryTypeId = 10) as ClosedPosts,
        count(distinct ph.Id) filter (where ph.PostHistoryTypeId = 11) as ReopenedPosts,
        max(p.CreationDate) as LastPostDate,
        min(p.CreationDate) as FirstPostDate,
        avg(p.Score) as AveragePostScore
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join PostHistory ph on ph.PostId = p.Id
    group by u.Id, u.DisplayName
),
QuestionAnswerPairs as (
    select
        q.Id as QuestionId,
        q.Title as QuestionTitle,
        a.Id as AnswerId,
        a.Score as AnswerScore,
        a.OwnerUserId as AnswerOwnerUserId,
        a.CreationDate as AnswerCreationDate,
        case when a.Id = q.AcceptedAnswerId then 1 else 0 end as IsAccepted,
        dense_rank() over (partition by q.Id order by a.Score desc, a.CreationDate asc) as AnswerRank
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
),
DuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        p1.Title as PostTitle,
        p2.Title as RelatedPostTitle
    from PostLinks pl
    join Posts p1 on p1.Id = pl.PostId
    join Posts p2 on p2.Id = pl.RelatedPostId
    where pl.LinkTypeId = 3
),
FinalResults as (
    select
        uac.UserId,
        uac.DisplayName,
        uac.TotalPosts,
        uac.ClosedPosts,
        uac.ReopenedPosts,
        uac.LastPostDate,
        uac.FirstPostDate,
        uac.AveragePostScore,
        ubc.GoldBadges,
        ubc.SilverBadges,
        ubc.BronzeBadges,
        ts.TagName as PopularTag,
        ts.ViewCount as TagViewCount,
        tq.Title as TopQuestionTitle,
        tq.Score as TopQuestionScore,
        tq.CommentCount as TopQuestionComments,
        tq.UpVotes as TopQuestionUpVotes,
        tq.DownVotes as TopQuestionDownVotes,
        qa.QuestionId,
        qa.AnswerId,
        qa.AnswerScore,
        qa.IsAccepted,
        dl.RelatedPostTitle as DuplicateOf
    from UserActivitySummary uac
    left join UserBadgeCounts ubc on ubc.UserId = uac.UserId
    left join RecursiveTagStats ts on ts.RankByViews = 1
    left join TopQuestions tq on tq.OwnerUserId = uac.UserId and tq.RankByScorePerUser = 1
    left join QuestionAnswerPairs qa on qa.AnswerOwnerUserId = uac.UserId and qa.AnswerRank = 1
    left join DuplicateLinks dl on dl.PostId = qa.QuestionId
    where uac.TotalPosts > 10
)
select
    UserId,
    DisplayName,
    TotalPosts,
    ClosedPosts,
    ReopenedPosts,
    LastPostDate,
    FirstPostDate,
    round(cast(AveragePostScore as numeric), 2) as AveragePostScore,
    GoldBadges,
    SilverBadges,
    BronzeBadges,
    PopularTag,
    TagViewCount,
    TopQuestionTitle,
    TopQuestionScore,
    TopQuestionComments,
    TopQuestionUpVotes,
    TopQuestionDownVotes,
    AnswerId,
    AnswerScore,
    IsAccepted,
    DuplicateOf
from FinalResults
order by TotalPosts desc, AveragePostScore desc
limit 100;