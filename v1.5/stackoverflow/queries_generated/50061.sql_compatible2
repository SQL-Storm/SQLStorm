WITH TaggedQuestions AS (
    -- 1. Identify all questions from a specific year with a high-volume tag and positive score.
    SELECT
        p.Id AS QuestionId,
        p.OwnerUserId AS QuestionOwnerId,
        p.Score AS QuestionScore,
        p.AnswerCount,
        p.FavoriteCount
    FROM Posts p
    WHERE p.PostTypeId = 1 -- 1 = Question
      AND p.Tags LIKE '%<sql>%'
      AND p.Score > 0
      AND p.CreationDate >= TIMESTAMP '2021-01-01 00:00:00'
      AND p.CreationDate < TIMESTAMP '2022-01-01 00:00:00'
      AND p.AnswerCount > 1
),
Answerers AS (
    -- 2. Find users who answered these questions and calculate their stats for those answers.
    SELECT
        a.OwnerUserId,
        q.QuestionId,
        a.Id AS AnswerId,
        a.Score AS AnswerScore,
        (CAST(EXTRACT(epoch FROM a.CreationDate) AS bigint)) - (CAST(EXTRACT(epoch FROM p_q.CreationDate) AS bigint)) AS TimeToAnswer
    FROM Posts a
    JOIN TaggedQuestions q ON a.ParentId = q.QuestionId
    JOIN Posts p_q ON q.QuestionId = p_q.Id
    WHERE a.PostTypeId = 2 -- 2 = Answer
      AND a.OwnerUserId IS NOT NULL
),
UserAggregatedStats AS (
    -- 3. Aggregate stats per user: count of answers, avg score, avg time to answer.
    SELECT
        ans.OwnerUserId,
        COUNT(DISTINCT ans.AnswerId) AS TotalAnswers,
        AVG(ans.AnswerScore) AS AverageAnswerScore,
        AVG(EXTRACT(EPOCH FROM (TIMESTAMP '1970-01-01 00:00:00' + INTERVAL '1 second' * ans.TimeToAnswer))) AS AvgSecondsToAnswer,
        SUM(ans.AnswerScore) AS TotalScoreContribution
    FROM Answerers ans
    GROUP BY ans.OwnerUserId
    HAVING COUNT(DISTINCT ans.AnswerId) > 5 -- Only consider users with more than 5 answers in this tag/year
),
UserRank AS (
    -- 4. Rank users based on their contribution and join with user details and badge counts.
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
        ROW_NUMBER() OVER (ORDER BY s.TotalScoreContribution DESC, s.AverageAnswerScore DESC) as Rank
    FROM UserAggregatedStats s
    JOIN Users u ON s.OwnerUserId = u.Id
    WHERE u.Reputation > 1000
)
-- 5. Final selection and further analysis.
-- Find the top 100 ranked users and join with their most recent activity (last answer, last comment).
SELECT
    ur.Rank,
    ur.DisplayName,
    ur.Reputation,
    ur.TotalAnswers,
    ur.AverageAnswerScore,
    ur.AvgSecondsToAnswer / 3600 AS AvgHoursToAnswer,
    ur.TotalScoreContribution,
    ur.GoldBadges,
    ur.SilverBadges,
    ur.BronzeBadges,
    (ur.GoldBadges * 10 + ur.SilverBadges * 5 + ur.BronzeBadges) AS BadgeScore,
    latest_post.LastActivityDate AS LastPostActivity,
    latest_comment.LastCommentDate
FROM UserRank ur
LEFT JOIN (
    SELECT
        p.OwnerUserId AS UserId,
        MAX(p.LastActivityDate) AS LastActivityDate
    FROM Posts p
    GROUP BY p.OwnerUserId
) latest_post ON latest_post.UserId = ur.UserId
LEFT JOIN (
    SELECT
        c.UserId AS UserId,
        MAX(c.CreationDate) AS LastCommentDate
    FROM Comments c
    GROUP BY c.UserId
) latest_comment ON latest_comment.UserId = ur.UserId
WHERE ur.Rank <= 100
ORDER BY ur.Rank;