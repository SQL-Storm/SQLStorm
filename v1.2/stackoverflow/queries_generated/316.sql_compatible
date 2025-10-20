with RecursiveUserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        count(p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        coalesce(sum(p.Score),0) as TotalPostScore,
        row_number() over (order by u.Reputation desc, u.LastAccessDate desc) as UserRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
TopUsersCTE as (
    select UserId, DisplayName, Reputation, QuestionCount, AnswerCount, TotalPostScore, UserRank
    from RecursiveUserActivity
    where UserRank <= 100
),
UserBadgeCounts as (
    select
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        count(*) as TotalBadges
    from Badges b
    where b.UserId in (select UserId from TopUsersCTE)
    group by b.UserId
),
UserPostStats as (
    select
        p.OwnerUserId as UserId,
        avg(p.Score) as AvgPostScore,
        max(p.Score) as MaxPostScore,
        min(p.Score) as MinPostScore,
        count(distinct p.Id) as TotalPosts,
        count(distinct case when p.PostTypeId = 1 then p.Id end) as Questions,
        count(distinct case when p.PostTypeId = 2 then p.Id end) as Answers,
        sum(coalesce(p.ViewCount,0)) as TotalViews,
        sum(coalesce(p.FavoriteCount,0)) as TotalFavorites
    from Posts p
    where p.OwnerUserId in (select UserId from TopUsersCTE)
    group by p.OwnerUserId
),
UserCommentStats as (
    select
        c.UserId,
        count(c.Id) as CommentCount,
        avg(c.Score) as AvgCommentScore,
        max(c.Score) as MaxCommentScore,
        min(c.Score) as MinCommentScore
    from Comments c
    where c.UserId in (select UserId from TopUsersCTE)
    group by c.UserId
),
UserVoteStats as (
    select
        v.UserId,
        count(v.Id) as VoteCount,
        sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotes,
        sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotes,
        sum(case when vt.Name = 'Favorite' then 1 else 0 end) as FavoritesGiven
    from Votes v
    join VoteTypes vt on vt.Id = v.VoteTypeId
    where v.UserId in (select UserId from TopUsersCTE)
    group by v.UserId
),
UserAggregatedStats as (
    select
        u.UserId,
        u.DisplayName,
        u.Reputation,
        u.QuestionCount,
        u.AnswerCount,
        u.TotalPostScore,
        coalesce(b.GoldBadges,0) as GoldBadges,
        coalesce(b.SilverBadges,0) as SilverBadges,
        coalesce(b.BronzeBadges,0) as BronzeBadges,
        coalesce(b.TotalBadges,0) as TotalBadges,
        coalesce(ps.AvgPostScore,0) as AvgPostScore,
        coalesce(ps.MaxPostScore,0) as MaxPostScore,
        coalesce(ps.MinPostScore,0) as MinPostScore,
        coalesce(ps.TotalPosts,0) as TotalPosts,
        coalesce(ps.Questions,0) as Questions,
        coalesce(ps.Answers,0) as Answers,
        coalesce(ps.TotalViews,0) as TotalViews,
        coalesce(ps.TotalFavorites,0) as TotalFavorites,
        coalesce(cs.CommentCount,0) as CommentCount,
        coalesce(cs.AvgCommentScore,0) as AvgCommentScore,
        coalesce(cs.MaxCommentScore,0) as MaxCommentScore,
        coalesce(cs.MinCommentScore,0) as MinCommentScore,
        coalesce(vs.VoteCount,0) as VoteCount,
        coalesce(vs.UpVotes,0) as UpVotes,
        coalesce(vs.DownVotes,0) as DownVotes,
        coalesce(vs.FavoritesGiven,0) as FavoritesGiven
    from TopUsersCTE u
    left join UserBadgeCounts b on b.UserId = u.UserId
    left join UserPostStats ps on ps.UserId = u.UserId
    left join UserCommentStats cs on cs.UserId = u.UserId
    left join UserVoteStats vs on vs.UserId = u.UserId
),
RankedPosts as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Title,
        p.Tags,
        row_number() over (partition by p.OwnerUserId order by p.Score desc, p.ViewCount desc) as PostRank
    from Posts p
    where p.OwnerUserId in (select UserId from TopUsersCTE)
),
TopPostsWithDuplicates as (
    select
        rp.Id,
        rp.PostTypeId,
        rp.OwnerUserId,
        rp.Score,
        rp.ViewCount,
        rp.CreationDate,
        rp.Title,
        rp.Tags,
        rp.PostRank,
        pl.RelatedPostId,
        lt.Name as LinkTypeName,
        (select count(*) from PostLinks pl2 where pl2.PostId = rp.Id and pl2.LinkTypeId = 3) as DuplicateCount
    from RankedPosts rp
    left join PostLinks pl on pl.PostId = rp.Id and pl.LinkTypeId = 3
    left join LinkTypes lt on lt.Id = pl.LinkTypeId
    where rp.PostRank <= 5
),
PostsWithCloseInfo as (
    select
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.CreationDate,
        p.ClosedDate,
        ph.Comment as CloseReasonId,
        crt.Name as CloseReasonName
    from Posts p
    left join PostHistory ph on ph.PostId = p.Id and ph.PostHistoryTypeId = 10
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as smallint)
    where p.PostTypeId = 1
),
QuestionsWithAnswerStats as (
    select
        q.Id as QuestionId,
        q.Title,
        q.OwnerUserId,
        q.CreationDate,
        q.ClosedDate,
        qci.CloseReasonName,
        count(a.Id) as AnswerCount,
        avg(a.Score) as AvgAnswerScore,
        max(a.Score) as MaxAnswerScore,
        min(a.Score) as MinAnswerScore,
        sum(case when a.Id = q.AcceptedAnswerId then 1 else 0 end) as HasAcceptedAnswer,
        q.AcceptedAnswerId
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    left join PostsWithCloseInfo qci on qci.Id = q.Id
    where q.PostTypeId = 1
    group by q.Id, q.Title, q.OwnerUserId, q.CreationDate, q.ClosedDate, qci.CloseReasonName, q.AcceptedAnswerId
),
QuestionsWithAnswerStatsFiltered as (
    select *
    from QuestionsWithAnswerStats
    where AnswerCount > 0 and (ClosedDate is null or ClosedDate > (cast('2024-10-01 12:34:56' as timestamp) - interval '1 year'))
),
UserQuestionSummary as (
    select
        u.UserId,
        count(q.QuestionId) as OpenQuestionsWithAnswers,
        avg(q.AvgAnswerScore) as AvgAnswerScoreOnQuestions,
        sum(q.HasAcceptedAnswer) as TotalAcceptedAnswers,
        count(distinct case when q.CloseReasonName is not null then q.QuestionId end) as ClosedQuestionsCount
    from TopUsersCTE u
    left join QuestionsWithAnswerStatsFiltered q on q.OwnerUserId = u.UserId
    group by u.UserId
)
select
    uas.UserId,
    uas.DisplayName,
    uas.Reputation,
    uas.QuestionCount,
    uas.AnswerCount,
    uas.TotalPostScore,
    uas.GoldBadges,
    uas.SilverBadges,
    uas.BronzeBadges,
    uas.TotalBadges,
    uas.AvgPostScore,
    uas.MaxPostScore,
    uas.MinPostScore,
    uas.TotalPosts,
    uas.Questions,
    uas.Answers,
    uas.TotalViews,
    uas.TotalFavorites,
    uas.CommentCount,
    uas.AvgCommentScore,
    uas.MaxCommentScore,
    uas.MinCommentScore,
    uas.VoteCount,
    uas.UpVotes,
    uas.DownVotes,
    uas.FavoritesGiven,
    uqs.OpenQuestionsWithAnswers,
    uqs.AvgAnswerScoreOnQuestions,
    uqs.TotalAcceptedAnswers,
    uqs.ClosedQuestionsCount,
    tp.Id as TopPostId,
    tp.PostTypeId as TopPostType,
    tp.Score as TopPostScore,
    tp.ViewCount as TopPostViews,
    tp.Title as TopPostTitle,
    tp.Tags as TopPostTags,
    tp.DuplicateCount as TopPostDuplicateCount,
    tp.LinkTypeName as TopPostLinkTypeName
from UserAggregatedStats uas
left join UserQuestionSummary uqs on uqs.UserId = uas.UserId
left join TopPostsWithDuplicates tp on tp.OwnerUserId = uas.UserId and tp.PostRank = 1
order by uas.Reputation desc, uas.TotalPostScore desc
limit 50;