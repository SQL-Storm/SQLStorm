-- {"query": "2163.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1512} 
with RecursiveTagCounts as (
    select
        t.Id,
        t.TagName,
        t.Count,
        p.OwnerUserId,
        p.CreationDate,
        row_number() over (partition by p.OwnerUserId order by p.CreationDate desc) as rn
    from Tags t
    join Posts p on p.PostTypeId = 1 and p.Tags like '%' || t.TagName || '%'
    where t.IsModeratorOnly = 0 and t.IsRequired = 0
), LatestUserTaggedQuestions as (
    select
        rtc.Id as TagId,
        rtc.TagName,
        rtc.Count,
        rtc.OwnerUserId,
        rtc.CreationDate
    from RecursiveTagCounts rtc
    where rtc.rn = 1
), UserBadgeSummary as (
    select
        b.UserId,
        b.Class,
        count(*) as BadgeCount,
        sum(case when b.TagBased = 1 then 1 else 0 end) as TagBasedBadges
    from Badges b
    group by b.UserId, b.Class
), UserActivityRanks as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        sum(case when p.PostTypeId = 1 then 1 else 0 end) as TotalQuestions,
        sum(case when p.PostTypeId = 2 then 1 else 0 end) as TotalAnswers,
        max(p.CreationDate) as LastPostDate,
        row_number() over (order by u.Reputation desc, u.Views desc) as ReputationRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Views, u.UpVotes, u.DownVotes
), PostLinkDupesAggregate as (
    select
        pl.PostId,
        count(distinct case when pl.LinkTypeId = 3 then pl.RelatedPostId end) as DuplicateCount,
        count(distinct case when pl.LinkTypeId = 1 then pl.RelatedPostId end) as LinkedCount
    from PostLinks pl
    group by pl.PostId
), TopQuestionsWithDupes as (
    select
        p.Id,
        p.Title,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.CreationDate,
        pl.DuplicateCount,
        pl.LinkedCount,
        row_number() over (order by p.Score desc, p.ViewCount desc) as RN
    from Posts p
    left join PostLinkDupesAggregate pl on pl.PostId = p.Id
    where p.PostTypeId = 1
), UserRecentActivityCTE as (
    select
        ph.PostId,
        ph.UserId,
        ph.PostHistoryTypeId,
        ph.CreationDate,
        u.DisplayName,
        ph.Text,
        row_number() over (partition by ph.UserId order by ph.CreationDate desc) as rn
    from PostHistory ph
    left join Users u on u.Id = ph.UserId
    where ph.UserId is not null
), UserLatestActivity as (
    select
        UserId,
        PostId,
        PostHistoryTypeId,
        CreationDate,
        DisplayName,
        Text
    from UserRecentActivityCTE
    where rn = 1
), UserAnswerStats as (
    select
        p.OwnerUserId,
        count(*) as AnswerCount,
        avg(p.Score) as AvgAnswerScore,
        sum(case when p.Score >= 10 then 1 else 0 end) as HighScoreAnswers
    from Posts p
    where p.PostTypeId = 2
    group by p.OwnerUserId
), UserQuestionStats as (
    select
        p.OwnerUserId,
        count(*) as QuestionCount,
        avg(p.Score) as AvgQuestionScore,
        sum(case when p.ViewCount > 1000 then 1 else 0 end) as PopularQuestions
    from Posts p
    where p.PostTypeId = 1
    group by p.OwnerUserId
), ComplexUserSummary as (
    select
        u.UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        coalesce(qs.QuestionCount, 0) as QuestionCount,
        coalesce(us.AnswerCount, 0) as AnswerCount,
        coalesce(qs.AvgQuestionScore, 0)::numeric(10,2) as AvgQuestionScore,
        coalesce(us.AvgAnswerScore, 0)::numeric(10,2) as AvgAnswerScore,
        coalesce(qs.PopularQuestions, 0) as PopularQuestions,
        coalesce(us.HighScoreAnswers, 0) as HighScoreAnswers,
        coalesce(bds.BadgeCount, 0) as TotalBadges,
        coalesce(bds.TagBasedBadges, 0) as TagBadges,
        rla.PostHistoryTypeId,
        rla.CreationDate as LastActivityDate,
        rla.Text as LastActivityText
    from UserActivityRanks u
    left join UserQuestionStats qs on qs.OwnerUserId = u.UserId
    left join UserAnswerStats us on us.OwnerUserId = u.UserId
    left join UserBadgeSummary bds on bds.UserId = u.UserId
    left join UserLatestActivity rla on rla.UserId = u.UserId
    where u.Reputation > 1000
)
select
    c.UserId,
    c.DisplayName,
    concat('Rep: ', c.Reputation, ', Views: ', c.Views, ', UpVotes: ', c.UpVotes, ', DownVotes: ', c.DownVotes) as UserReputationStats,
    concat('QCount: ', c.QuestionCount, ', AvgQScore: ', c.AvgQuestionScore, ', PopularQ: ', c.PopularQuestions) as QuestionStats,
    concat('ACount: ', c.AnswerCount, ', AvgAScore: ', c.AvgAnswerScore, ', HiScoreA: ', c.HighScoreAnswers) as AnswerStats,
    concat('Badges: ', c.TotalBadges, ' (TagBased: ', c.TagBadges, ')') as BadgeInfo,
    c.LastActivityDate,
    left(coalesce(c.LastActivityText, ''), 100) as LastActivitySnippet,
    coalesce(lq.Title, 'No top question') as TopQuestionTitle,
    coalesce(lq.Score, 0) as TopQuestionScore,
    coalesce(lq.ViewCount, 0) as TopQuestionViews,
    coalesce(lq.DuplicateCount, 0) as TopQuestionDuplicates,
    coalesce(lq.LinkedCount, 0) as TopQuestionLinks
from ComplexUserSummary c
left join TopQuestionsWithDupes lq on lq.OwnerUserId = c.UserId and lq.RN = 1
where c.AnswerCount > 10
order by c.Reputation desc, c.QuestionCount desc, c.AnswerCount desc
limit 50;