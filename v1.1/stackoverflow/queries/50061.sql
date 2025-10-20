WITH TaggedQuestions AS (
    SELECT
        p.Id AS QuestionId,
        p.OwnerUserId AS QuestionOwnerId,
        p.Score AS QuestionScore,
        p.AnswerCount,
        p.FavoriteCount,
        p.CreationDate
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.Tags LIKE '%<sql>%'
      AND p.Score > 0
      AND p.CreationDate >= DATE '2021-01-01' AND p.CreationDate < DATE '2022-01-01'
      AND p.AnswerCount > 1
),
Answerers AS (
    SELECT
        a.OwnerUserId,
        q.QuestionId,
        a.Id AS AnswerId,
        a.Score AS AnswerScore,
        -- Standard SQL timestamp difference to interval might vary by dialect.
        -- Use extract epoch from (a.CreationDate - p_q.CreationDate) where supported,
        -- otherwise store interval and handle in aggregation.
        (a.CreationDate - p_q.CreationDate) AS TimeToAnswer,
        a.CreationDate,
        p_q.CreationDate AS QuestionCreationDate
    FROM Posts a
    JOIN TaggedQuestions q ON a.ParentId = q.QuestionId
    JOIN Posts p_q ON q.QuestionId = p_q.Id
    WHERE a.PostTypeId = 2
      AND a.OwnerUserId IS NOT NULL
),
UserAggregatedStats AS (
    SELECT
        ans.OwnerUserId,
        COUNT(DISTINCT ans.AnswerId) AS TotalAnswers,
        AVG(ans.AnswerScore) AS AverageAnswerScore,
        AVG(EXTRACT(EPOCH FROM (ans.TimeToAnswer))) AS AvgSecondsToAnswer,
        SUM(ans.AnswerScore) AS TotalScoreContribution
    FROM Answerers ans
    GROUP BY ans.OwnerUserId
    HAVING COUNT(DISTINCT ans.AnswerId) > 5
),
UserRank AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        s.TotalAnswers,
        s.AverageAnswerScore,
        s.AvgSecondsToAnswer,
        s.TotalScoreContribution,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS SilverBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) AS BronzeBadges,
        ROW_NUMBER() OVER (ORDER BY s.TotalScoreContribution DESC, s.AverageAnswerScore DESC) AS Rank
    FROM UserAggregatedStats s
    JOIN Users u ON s.OwnerUserId = u.Id
    WHERE u.Reputation > 1000
)
SELECT
    ur.Rank,
    ur.DisplayName,
    ur.Reputation,
    ur.TotalAnswers,
    ur.AverageAnswerScore,
    ur.AvgSecondsToAnswer / 3600.0 AS AvgHoursToAnswer,
    ur.TotalScoreContribution,
    ur.GoldBadges,
    ur.SilverBadges,
    ur.BronzeBadges,
    (ur.GoldBadges * 10 + ur.SilverBadges * 5 + ur.BronzeBadges) AS BadgeScore,
    latest_post.LastActivityDate AS LastPostActivity,
    latest_comment.LastCommentDate
FROM UserRank ur
LEFT JOIN (
    SELECT p.OwnerUserId AS UserId, MAX(p.LastActivityDate) AS LastActivityDate
    FROM Posts p
    GROUP BY p.OwnerUserId
) AS latest_post ON latest_post.UserId = ur.UserId
LEFT JOIN (
    SELECT c.UserId, MAX(c.CreationDate) AS LastCommentDate
    FROM Comments c
    GROUP BY c.UserId
) AS latest_comment ON latest_comment.UserId = ur.UserId
WHERE ur.Rank <= 100
ORDER BY ur.Rank;