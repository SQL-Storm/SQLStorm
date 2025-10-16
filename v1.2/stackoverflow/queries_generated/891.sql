-- {"query": "891.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.8, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1330} 
with RecursiveTagCounts as (
    select t.Id as TagId, t.TagName, coalesce(p.AnswerCount,0) as AnswerCount, coalesce(p.ViewCount,0) as ViewCount,
           u.Reputation as OwnerReputation,
           dense_rank() over (partition by t.Id order by p.CreationDate desc) as RecentRank
    from Tags t
    left join Posts p on p.Id = t.ExcerptPostId and p.PostTypeId = 1
    left join Users u on u.Id = p.OwnerUserId
    where t.IsModeratorOnly = 0 and t.IsRequired = 0
),
FilteredTagRanks as (
    select TagId, TagName, AnswerCount, ViewCount, OwnerReputation
    from RecursiveTagCounts
    where RecentRank <= 3
),
UserBadgeRankings as (
    select u.Id as UserId, u.DisplayName,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges,
        row_number() over (order by count(b.Id) desc, u.Reputation desc) as BadgeRank
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
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
           row_number() over (partition by q.Id order by a.Score desc nulls last) as AnswerRank
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1 and q.CreationDate > current_date - interval '180 days'
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
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where ph.CreationDate > current_date - interval '365 days'
),
AggregatedUserStats as (
    select u.Id, u.DisplayName, u.Reputation, count(p.Id) filter (where p.PostTypeId = 1) as QuestionsAsked,
           count(p.Id) filter (where p.PostTypeId = 2) as AnswersProvided,
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
    left join ClosedPostHistory ph on ph.PostId in (select Id from Posts where OwnerUserId = u.Id)
    group by u.Id, u.DisplayName, u.Reputation, v2.UpVotes
),
RankedUsersByActivity as (
    select *, rank() over (order by QuestionsAsked desc, AnswersProvided desc) as ActivityRank
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
    join RankedUsersByActivity ru on ru.DisplayName = tu.DisplayName
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