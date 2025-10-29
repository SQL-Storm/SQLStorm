-- {"query": "4125.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 953}
WITH UserPostStats AS (
    SELECT
        p.OwnerUserId,
        p.PostTypeId,
        COUNT(p.Id) AS PostCount,
        AVG(p.Score) AS AvgScore,
        SUM(CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END) AS ClosedPostCount,
        MAX(p.CreationDate) AS LatestPostDate
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId, p.PostTypeId
),
UserCommentStats AS (
    SELECT
        c.UserId,
        COUNT(c.Id) AS CommentCount,
        AVG(c.Score) AS AvgCommentScore,
        SUM(CASE WHEN c.CreationDate < (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1' YEAR) THEN 1 ELSE 0 END) AS OlderCommentCount
    FROM Comments c
    WHERE c.UserId IS NOT NULL
    GROUP BY c.UserId
),
RankedUsers AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.Id) AS ReputationRank,
        u.CreationDate
    FROM Users u
    WHERE u.Id > 0 AND u.DisplayName IS NOT NULL
),
HighEngagementUsers AS (
    SELECT
        ru.Id,
        ru.DisplayName,
        ru.Reputation,
        ru.ReputationRank,
        ru.CreationDate
    FROM RankedUsers ru
    INNER JOIN UserCommentStats ucs ON ru.Id = ucs.UserId
    WHERE ru.ReputationRank <= 1000
      AND ucs.CommentCount > 50
      AND ucs.AvgCommentScore > 0
)
SELECT
    heu.DisplayName AS HighEngagementUser,
    heu.Reputation,
    ps_q.PostCount AS QuestionCount,
    COALESCE(ps_a.PostCount, 0) AS AnswerCount,
    COALESCE(ucs.CommentCount, 0) AS TotalComments,
    CASE
        WHEN ps_q.AvgScore > 10 THEN 'Highly Rated Questioner'
        WHEN ps_a.AvgScore > 5 THEN 'Highly Rated Answerer'
        ELSE 'Moderately Active'
    END AS UserActivityLevel,
    CASE
        WHEN heu.ReputationRank BETWEEN 1 AND 100 THEN 'Top 1%'
        WHEN heu.ReputationRank BETWEEN 101 AND 500 THEN 'Top 5%'
        ELSE 'Top 10%'
    END AS ReputationTier,
    COALESCE(ps_q.ClosedPostCount, 0) AS ClosedQuestions,
    CAST(DATE_PART('epoch', (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - heu.CreationDate)) / 86400 AS INTEGER) AS DaysSinceCreation,
    CASE
        WHEN ps_q.LatestPostDate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30' DAY) THEN 'Recent Activity'
        ELSE 'Lapsed Activity'
    END AS ActivityStatus,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = heu.Id AND b.Class = 1) AS GoldBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = heu.Id AND b.Class = 2) AS SilverBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = heu.Id AND b.Class = 3) AS BronzeBadges,
    CASE
        WHEN EXISTS (
            SELECT 1
            FROM PostLinks pl
            JOIN Posts p ON pl.PostId = p.Id
            WHERE pl.RelatedPostId = heu.Id AND pl.LinkTypeId = 3
        ) THEN 'Has Duplicates Pointing To'
        ELSE 'No Duplicates Pointing To'
    END AS LinkStatus
FROM HighEngagementUsers heu
LEFT JOIN UserPostStats ps_q ON heu.Id = ps_q.OwnerUserId AND ps_q.PostTypeId = 1
LEFT JOIN UserPostStats ps_a ON heu.Id = ps_a.OwnerUserId AND ps_a.PostTypeId = 2
LEFT JOIN UserCommentStats ucs ON heu.Id = ucs.UserId
WHERE heu.Reputation > 1000
GROUP BY
    heu.DisplayName,
    heu.Reputation,
    ps_q.PostCount,
    ps_a.PostCount,
    ucs.CommentCount,
    ps_q.AvgScore,
    ps_a.AvgScore,
    heu.ReputationRank,
    ps_q.ClosedPostCount,
    heu.CreationDate,
    ps_q.LatestPostDate,
    heu.Id
ORDER BY heu.Reputation DESC
LIMIT 100;