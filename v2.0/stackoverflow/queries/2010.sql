-- {"query": "2010.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1447}
with RecursiveUserBadgeCounts as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges,
        row_number() over (order by u.Reputation desc, u.Id) as UserRank
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation
),
QuestionsWithAnswers as (
    select
        p.Id as QuestionId,
        p.Title,
        p.Tags,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.AcceptedAnswerId,
        u.DisplayName as OwnerName,
        coalesce(ans.AnswerCount,0) as AnswerCount,
        coalesce(ans.MaxScore, 0) as MaxAnswerScore,
        row_number() over (partition by p.OwnerUserId order by p.Score desc, p.CreationDate) as UserQuestionRank,
        p.OwnerUserId
    from Posts p
    left join lateral (
        select
            count(*) as AnswerCount,
            max(score) as MaxScore
        from Posts ans
        where ans.ParentId = p.Id and ans.PostTypeId = 2
    ) ans on true
    left join Users u on u.Id = p.OwnerUserId
    where p.PostTypeId = 1
),
CloseAndReopenCounts as (
    select
        ph.PostId,
        sum(case when ph.PostHistoryTypeId = 10 then 1 else 0 end) as CloseVotes,
        sum(case when ph.PostHistoryTypeId = 11 then 1 else 0 end) as ReopenVotes
    from PostHistory ph
    where ph.PostHistoryTypeId in (10,11)
    group by ph.PostId
),
QuestionLinks as (
    select
        pl.PostId,
        count(distinct case when pl.LinkTypeId=3 then pl.RelatedPostId end) as DuplicateCount,
        count(distinct case when pl.LinkTypeId=1 then pl.RelatedPostId end) as LinkedCount
    from PostLinks pl
    group by pl.PostId
),
UserLastActivity as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        u.Location,
        p.LastActivityDate,
        row_number() over (partition by u.Id order by p.LastActivityDate desc) as rn
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
),
TagUsageStats as (
    select
        tag,
        count(distinct p.Id) as QuestionsWithTag,
        avg(p.Score) as AvgQuestionScore,
        sum(p.ViewCount) as TotalViews
    from (
        select p.Id,
            unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags)-2), '><')) as tag,
            p.Score,
            p.ViewCount
        from Posts p
        where p.PostTypeId = 1 and p.Tags is not null
    ) p
    group by tag
),
TopScoringAnswers as (
    select
        a.ParentId as QuestionId,
        a.Id as AnswerId,
        a.Score as AnswerScore,
        a.CreationDate as AnswerDate,
        u.DisplayName as AnswerOwner
    from Posts a
    left join Users u on u.Id = a.OwnerUserId
    where a.PostTypeId = 2 and a.Score > (
        select avg(score) + stddev_pop(score) from Posts where PostTypeId = 2
    )
),
UserReputationTrend as (
    select
        u.Id as UserId,
        date_trunc('month', ph.CreationDate) as Month,
        sum(case when ph.PostHistoryTypeId in (1,2,3,4,5,6,7,8,9) then 10 else 0 end) as EditsContribution,
        count(distinct ph.PostId) as PostsEdited,
        count(distinct case when ph.PostHistoryTypeId = 10 then ph.PostId end) as ClosedPosts
    from Users u
    left join PostHistory ph on ph.UserId = u.Id
    where ph.CreationDate >= u.CreationDate and ph.CreationDate < cast('2024-10-01 12:34:56' as timestamp)
    group by u.Id, Month
),
HighImpactQuestions as (
    select
        q.QuestionId,
        q.Title,
        q.Score,
        q.ViewCount,
        q.AnswerCount,
        q.AcceptedAnswerId,
        q.OwnerName,
        q.CreationDate,
        coalesce(clc.CloseVotes, 0) as CloseVotes,
        coalesce(clc.ReopenVotes, 0) as ReopenVotes,
        coalesce(ql.DuplicateCount, 0) as DuplicateLinks,
        coalesce(ql.LinkedCount, 0) as LinkedCount,
        q.Tags
    from QuestionsWithAnswers q
    left join CloseAndReopenCounts clc on clc.PostId = q.QuestionId
    left join QuestionLinks ql on ql.PostId = q.QuestionId
    where (q.Score > 10 or q.ViewCount > 1000)
      and coalesce(clc.CloseVotes, 0) < 5
      and q.AnswerCount > 0
)

select
    hiq.QuestionId,
    hiq.Title,
    hiq.Score,
    hiq.ViewCount,
    hiq.AnswerCount,
    hiq.AcceptedAnswerId,
    hiq.OwnerName,
    hiq.CreationDate,
    hiq.CloseVotes,
    hiq.ReopenVotes,
    hiq.DuplicateLinks,
    hiq.LinkedCount,
    rus.GoldBadges,
    rus.SilverBadges,
    rus.BronzeBadges,
    rus.UserRank,
    tgs.QuestionsWithTag,
    tgs.AvgQuestionScore,
    tgs.TotalViews,
    tsa.AnswerId as TopAnswerId,
    tsa.AnswerScore,
    tsa.AnswerDate,
    tsa.AnswerOwner
from HighImpactQuestions hiq
left join RecursiveUserBadgeCounts rus on rus.UserId = (
    select OwnerUserId from Posts where Id = hiq.QuestionId limit 1
)
left join TagUsageStats tgs on tgs.tag = (
    select tag from (
        select unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags)-2), '><')) as tag
        from Posts p
        where p.Id = hiq.QuestionId
        limit 1
    ) x
)
left join TopScoringAnswers tsa on tsa.QuestionId = hiq.QuestionId
order by hiq.Score desc, hiq.ViewCount desc, rus.UserRank
limit 50;