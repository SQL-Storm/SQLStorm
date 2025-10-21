-- {"query": "46085.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-4.5-sonnet", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 194990, "output_tokens": 156685} 

WITH TopUsersByReputation AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        DENSE_RANK() OVER (ORDER BY u.Reputation DESC) as rep_rank
    FROM Users u
    WHERE u.Reputation > 10000
),
QuestionMetrics AS (
    SELECT 
        p.Id as QuestionId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CreationDate,
        p.Tags,
        COALESCE(p.AcceptedAnswerId, 0) as AcceptedAnswerId,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 2) as UpVotes,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 3) as DownVotes,
        COUNT(DISTINCT c.Id) as CommentCount,
        AVG(a.Score) as AvgAnswerScore,
        MAX(a.Score) as MaxAnswerScore
    FROM Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN Posts a ON p.Id = a.ParentId AND a.PostTypeId = 2
    WHERE p.PostTypeId = 1
        AND p.CreationDate >= CURRENT_DATE - INTERVAL '3 years'
    GROUP BY p.Id, p.OwnerUserId, p.Score, p.ViewCount, p.AnswerCount, 
             p.CreationDate, p.Tags, p.AcceptedAnswerId
),
TagPerformance AS (
    SELECT 
        t.TagName,
        COUNT(DISTINCT qm.QuestionId) as QuestionCount,
        AVG(qm.Score) as AvgQuestionScore,
        AVG(qm.ViewCount) as AvgViews,
        SUM(qm.AnswerCount) as TotalAnswers,
        COUNT(DISTINCT CASE WHEN qm.AcceptedAnswerId > 0 THEN qm.QuestionId END) as QuestionsWithAcceptedAnswer
    FROM Tags t
    INNER JOIN QuestionMetrics qm ON qm.Tags LIKE '%<' || t.TagName || '>%'
    WHERE t.Count > 100
    GROUP BY t.TagName
    HAVING COUNT(DISTINCT qm.QuestionId) > 50
),
UserEngagementScore AS (
    SELECT 
        tu.Id,
        tu.DisplayName,
        tu.Reputation,
        COUNT(DISTINCT qm.QuestionId) as QuestionsAsked,
        COUNT(DISTINCT a.Id) as AnswersGiven,
        COUNT(DISTINCT b.Id) as BadgesEarned,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 1) as GoldBadges,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 2) as SilverBadges,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 3) as BronzeBadges,
        AVG(qm.Score) as AvgQuestionScore,
        AVG(a.Score) as AvgAnswerScore,
        COUNT(DISTINCT CASE WHEN a.Id = qm.AcceptedAnswerId THEN a.Id END) as AcceptedAnswers,
        SUM(CASE WHEN v.VoteTypeId = 8 THEN v.BountyAmount ELSE 0 END) as TotalBountiesOffered
    FROM TopUsersByReputation tu
    LEFT JOIN QuestionMetrics qm ON tu.Id = qm.OwnerUserId
    LEFT JOIN Posts a ON tu.Id = a.OwnerUserId AND a.PostTypeId = 2
    LEFT JOIN Badges b ON tu.Id = b.UserId
    LEFT JOIN Votes v ON tu.Id = v.UserId
    WHERE tu.rep_rank <= 1000
    GROUP BY tu.Id, tu.DisplayName, tu.Reputation
),
PostEditingActivity AS (
    SELECT 
        ph.PostId,
        COUNT(DISTINCT ph.Id) FILTER (WHERE ph.PostHistoryTypeId IN (4,5,6)) as EditCount,
        COUNT(DISTINCT ph.UserId) as UniqueEditors,
        MAX(ph.CreationDate) - MIN(ph.CreationDate) as EditTimespan,
        COUNT(DISTINCT ph.Id) FILTER (WHERE ph.PostHistoryTypeId IN (7,8,9)) as RollbackCount
    FROM PostHistory ph
    INNER JOIN QuestionMetrics qm ON ph.PostId = qm.QuestionId
    WHERE ph.PostHistoryTypeId IN (4,5,6,7,8,9)
    GROUP BY ph.PostId
)
SELECT 
    ues.DisplayName,
    ues.Reputation,
    ues.QuestionsAsked,
    ues.AnswersGiven,
    ues.AcceptedAnswers,
    ROUND(ues.AvgQuestionScore::numeric, 2) as AvgQuestionScore,
    ROUND(ues.AvgAnswerScore::numeric, 2) as AvgAnswerScore,
    ues.GoldBadges,
    ues.SilverBadges,
    ues.BronzeBadges,
    ues.TotalBountiesOffered,
    STRING_AGG(DISTINCT tp.TagName, ', ' ORDER BY tp.TagName) FILTER (WHERE tp.QuestionCount > 100) as TopTags,
    AVG(pea.EditCount) as AvgEditsPerQuestion,
    COUNT(DISTINCT pl.RelatedPostId) as LinkedPosts,
    ROUND(AVG(qm.ViewCount)::numeric, 0) as AvgViewsPerQuestion,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY qm.Score) as MedianQuestionScore,
    MAX(qm.Score) as MaxQuestionScore,
    COUNT(DISTINCT qm.QuestionId) FILTER (WHERE qm.AcceptedAnswerId > 0) as QuestionsWithAcceptedAnswers
FROM UserEngagementScore ues
LEFT JOIN QuestionMetrics qm ON ues.Id = qm.OwnerUserId
LEFT JOIN TagPerformance tp ON qm.Tags LIKE '%<' || tp.TagName || '>%'
LEFT JOIN PostEditingActivity pea ON qm.QuestionId = pea.PostId
LEFT JOIN PostLinks pl ON qm.QuestionId = pl.PostId AND pl.LinkTypeId = 1
WHERE ues.QuestionsAsked > 5 OR ues.AnswersGiven > 20
GROUP BY ues.Id, ues.DisplayName, ues.Reputation, ues.QuestionsAsked, 
         ues.AnswersGiven, ues.AcceptedAnswers, ues.AvgQuestionScore, 
         ues.AvgAnswerScore, ues.GoldBadges, ues.SilverBadges, 
         ues.BronzeBadges, ues.TotalBountiesOffered
HAVING COUNT(DISTINCT qm.QuestionId) > 0
ORDER BY ues.Reputation DESC, ues.AcceptedAnswers DESC
LIMIT 500;
