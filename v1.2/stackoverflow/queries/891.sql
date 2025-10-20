with RecursiveTagCounts as (
    select t.Id as TagId, t.TagName, coalesce(p.AnswerCount,0) as AnswerCount, coalesce(p.ViewCount,0) as ViewCount,
           u.Reputation as OwnerReputation,
           dense_rank() over (partition by t.Id order by p.CreationDate desc) as RecentRank
    from Tags t
    left join Posts p on p.Id = t.ExcerptPostId and p.PostTypeId = 1
    left join Users u on u.Id = p.OwnerUserId
    where t.IsModeratorOnly = false and t.IsRequired = false
),
FilteredTagRanks as (
    select TagId, TagName, AnswerCount, ViewCount, OwnerReputation
    from RecursiveTagCounts
    where RecentRank <= 3
),
UserBadgeRankings as (
    select u.Id as UserId, u.DisplayName,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        row_number() over (order by count(b.Id) desc, u.Reputation desc) as BadgeRank
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation
),
TopUsers as (
    select UserId, DisplayName, GoldBadges, SilverBadges, BronzeBadges
    from UserBadgeRankings
    where BadgeRank <= 100
),
PostVoteStats as (
    select p.Id as PostId, p.Title, p.PostTypeId,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
        sum(case when v.VoteTypeId = 5 then 1 else 0 end) as Favorites,
        count(v.Id) as TotalVotes
    from Posts p
    left join Votes v on v.PostId = p.Id
    group by p.Id, p.Title, p.PostTypeId
),
RecentQuestionsWithAnswers as (
    select q.Id as QuestionId, q.Title, q.OwnerUserId, q.CreationDate, q.Score, q.ViewCount,
           a.Id as AnswerId, a.Score as AnswerScore, a.CreationDate as AnswerCreationDate,
           row_number() over (partition by q.Id order by a.Score desc NULLS LAST) as AnswerRank
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1 and q.CreationDate > (CAST('2024-10-01' AS date) - INTERVAL '180' DAY)
),
TopAnswersPerQuestion as (
    select QuestionId, Title, OwnerUserId, CreationDate as QuestionCreationDate, Score as QuestionScore, ViewCount,
           AnswerId, AnswerScore, AnswerCreationDate
    from RecentQuestionsWithAnswers
    where AnswerRank = 1
),
ClosedPostHistory as (
    select ph.PostId, ph.CreationDate as CloseDate, crt.Name as CloseReason
    from PostHistory ph
    join PostHistoryTypes pht on ph.PostHistoryTypeId = pht.Id and pht.Name = 'Post Closed'
    left join CloseReasonTypes crt on crt.Id = CAST(ph.Comment AS INTEGER)
    where ph.CreationDate > (CAST('2024-10-01' AS date) - INTERVAL '365' DAY)
),
AggregatedUserStats as (
    select u.Id, u.DisplayName, u.Reputation,
           sum(case when p.PostTypeId = 1 then 1 else 0 end) as QuestionsAsked,
           sum(case when p.PostTypeId = 2 then 1 else 0 end) as AnswersProvided,
           count(distinct ph.PostId) as ClosedPostsOwned,
           sum(coalesce(v2.UpVotes,0)) as TotalUpVotesOnPosts
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join (
        select p.OwnerUserId, count(v.Id) as UpVotes
        from Posts p
        left join Votes v on v.PostId = p.Id and v.VoteTypeId = 2
        group by p.OwnerUserId
    ) v2 on v2.OwnerUserId = u.Id
    left join ClosedPostHistory ph on ph.PostId = (select Id from Posts p2 where p2.OwnerUserId = u.Id limit 1) -- replace IN-subquery with scalar to avoid non-inner join on subquery in some engines
    group by u.Id, u.DisplayName, u.Reputation, v2.UpVotes
),
RankedUsersByActivity as (
    select Id, DisplayName, Reputation, QuestionsAsked, AnswersProvided, ClosedPostsOwned, TotalUpVotesOnPosts,
           rank() over (order by QuestionsAsked desc, AnswersProvided desc) as ActivityRank
    from AggregatedUserStats
),
FinalDataSet as (
    select tu.DisplayName as UserName, tu.GoldBadges, tu.SilverBadges, tu.BronzeBadges,
           ru.QuestionsAsked, ru.AnswersProvided, ru.ClosedPostsOwned, ru.TotalUpVotesOnPosts,
           ta.QuestionId, ta.Title as QuestionTitle, ta.QuestionScore, ta.ViewCount as QuestionViews,
           ta.AnswerId, ta.AnswerScore, ta.AnswerCreationDate,
           pvs.UpVotes, pvs.DownVotes, pvs.Favorites, pvs.TotalVotes,
           crt.CloseReason
    from TopUsers tu
    join RankedUsersByActivity ru on ru.DisplayName = tu.DisplayName and ru.Id = tu.UserId
    left join TopAnswersPerQuestion ta on ta.OwnerUserId = ru.Id
    left join PostVoteStats pvs on pvs.PostId = ta.QuestionId
    left join ClosedPostHistory crt on crt.PostId = ta.QuestionId
    where ru.ActivityRank <= 50
)
select UserName, GoldBadges, SilverBadges, BronzeBadges,
       QuestionsAsked, AnswersProvided, ClosedPostsOwned, TotalUpVotesOnPosts,
       QuestionId, QuestionTitle,
       QuestionScore, QuestionViews,
       AnswerId, AnswerScore, AnswerCreationDate,
       UpVotes, DownVotes, Favorites, TotalVotes,
       coalesce(CloseReason, 'Open') as PostStatus
from FinalDataSet
order by TotalUpVotesOnPosts desc, QuestionViews desc, AnswerScore desc
limit 100;