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
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) as UpVotes,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END) as DownVotes,
        COUNT(DISTINCT c.Id) as CommentCount,
        AVG(a.Score) as AvgAnswerScore,
        MAX(a.Score) as MaxAnswerScore
    FROM Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN Posts a ON p.Id = a.ParentId AND a.PostTypeId = 2
    WHERE p.PostTypeId = 1
        AND p.CreationDate >= (CAST('2024-10-01' AS date) - INTERVAL '3' YEAR)
    GROUP BY p.Id, p.OwnerUserId, p.Score, p.ViewCount, p.AnswerCount, 
             p.CreationDate, p.Tags, COALESCE(p.AcceptedAnswerId, 0)
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
    INNER JOIN QuestionMetrics qm ON qm.Tags LIKE '%' || '<' || t.TagName || '>' || '%'
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
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) as GoldBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) as SilverBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) as BronzeBadges,
        AVG(qm.Score) as AvgQuestionScore,
        AVG(a.Score) as AvgAnswerScore,
        COUNT(DISTINCT CASE WHEN a.Id = qm.AcceptedAnswerId THEN a.Id END) as AcceptedAnswers,
        SUM(CASE WHEN v.VoteTypeId = 8 THEN COALESCE(v.BountyAmount,0) ELSE 0 END) as TotalBountiesOffered
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
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (4,5,6) THEN ph.Id END) as EditCount,
        COUNT(DISTINCT ph.UserId) as UniqueEditors,
        MAX(ph.CreationDate) - MIN(ph.CreationDate) as EditTimespan,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (7,8,9) THEN ph.Id END) as RollbackCount
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
    ROUND(CAST(ues.AvgQuestionScore AS NUMERIC), 2) as AvgQuestionScore,
    ROUND(CAST(ues.AvgAnswerScore AS NUMERIC), 2) as AvgAnswerScore,
    ues.GoldBadges,
    ues.SilverBadges,
    ues.BronzeBadges,
    ues.TotalBountiesOffered,
    STRING_AGG(tp.TagName, ', ' ORDER BY tp.TagName) as TopTags,
    AVG(pea.EditCount) as AvgEditsPerQuestion,
    COUNT(DISTINCT pl.RelatedPostId) as LinkedPosts,
    ROUND(CAST(AVG(qm.ViewCount) AS NUMERIC), 0) as AvgViewsPerQuestion,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY qm.Score) as MedianQuestionScore,
    MAX(qm.Score) as MaxQuestionScore,
    COUNT(DISTINCT CASE WHEN qm.AcceptedAnswerId > 0 THEN qm.QuestionId END) as QuestionsWithAcceptedAnswers,
    ues.Id
FROM UserEngagementScore ues
LEFT JOIN QuestionMetrics qm ON ues.Id = qm.OwnerUserId
LEFT JOIN TagPerformance tp ON qm.Tags LIKE '%' || '<' || tp.TagName || '>' || '%'
LEFT JOIN PostEditingActivity pea ON qm.QuestionId = pea.PostId
LEFT JOIN PostLinks pl ON qm.QuestionId = pl.PostId AND pl.LinkTypeId = 1
WHERE (ues.QuestionsAsked > 5 OR ues.AnswersGiven > 20)
GROUP BY ues.Id, ues.DisplayName, ues.Reputation, ues.QuestionsAsked, 
         ues.AnswersGiven, ues.AcceptedAnswers, ues.AvgQuestionScore, 
         ues.AvgAnswerScore, ues.GoldBadges, ues.SilverBadges, 
         ues.BronzeBadges, ues.TotalBountiesOffered
HAVING COUNT(DISTINCT qm.QuestionId) > 0
ORDER BY ues.Reputation DESC, ues.AcceptedAnswers DESC
LIMIT 500;