WITH RankedPostEdits AS (
    SELECT
        ph.PostId,
        ph.UserId,
        ph.CreationDate,
        ph.PostHistoryTypeId,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) as rn
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6)
),
UserPostActivity AS (
    SELECT
        p.OwnerUserId,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        AVG(p.Score) AS AvgPostScore,
        MAX(p.CreationDate) AS LatestPostDate
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
      AND p.OwnerUserId > 0
    GROUP BY p.OwnerUserId
),
UserContributionSummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COALESCE(upa.TotalPosts, 0) AS TotalPostsContributed,
        COALESCE(upa.QuestionCount, 0) AS TotalQuestions,
        COALESCE(upa.AnswerCount, 0) AS TotalAnswers,
        COALESCE(upa.AvgPostScore, 0.0) AS AverageScoreOfUserPosts,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        MAX(CASE WHEN rpe.PostHistoryTypeId IN (4, 5) THEN rpe.CreationDate ELSE NULL END) AS LastContentEditDate
    FROM Users u
    LEFT JOIN UserPostActivity upa ON u.Id = upa.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN RankedPostEdits rpe ON u.Id = rpe.UserId AND rpe.rn = 1
    WHERE u.DisplayName IS NOT NULL
      AND u.Id NOT IN (SELECT UserId FROM Votes WHERE VoteTypeId = 14)
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, upa.TotalPosts, upa.QuestionCount, upa.AnswerCount, upa.AvgPostScore
)
SELECT
    ucs.UserId,
    ucs.DisplayName,
    ucs.Reputation,
    ucs.UserCreationDate,
    ucs.TotalPostsContributed,
    ucs.TotalQuestions,
    ucs.TotalAnswers,
    ucs.AverageScoreOfUserPosts,
    ucs.BadgeCount,
    ucs.GoldBadges,
    ucs.SilverBadges,
    ucs.BronzeBadges,
    ucs.LastContentEditDate,
    SUM(CASE WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS AcceptedAnswersGiven,
    COUNT(DISTINCT ph.Id) AS PostHistoryEntries,
    MAX(p.LastActivityDate) AS UserLastPostActivity,
    CASE
        WHEN ucs.Reputation > 10000 THEN 'High Reputation'
        WHEN ucs.Reputation > 1000 THEN 'Medium Reputation'
        ELSE 'Low Reputation'
    END AS ReputationTier,
    COALESCE(
        (SELECT SUM(COALESCE(c.Score, 0))
         FROM Comments c
         WHERE c.UserId = ucs.UserId
         AND c.CreationDate BETWEEN ucs.UserCreationDate AND COALESCE(ucs.LastContentEditDate, ucs.UserCreationDate + INTERVAL '1 year')
        ), 0) AS TotalCommentScoreInFirstYear,
    (
        SELECT COUNT(*)
        FROM Posts p_inner
        WHERE p_inner.OwnerUserId = ucs.UserId
        AND p_inner.ClosedDate IS NOT NULL
    ) AS ClosedPostsByOwner
FROM UserContributionSummary ucs
LEFT JOIN Posts p ON ucs.UserId = p.OwnerUserId
LEFT JOIN PostHistory ph ON ucs.UserId = ph.UserId
WHERE ucs.UserCreationDate > DATE '2010-01-01'
  AND ucs.Reputation BETWEEN 100 AND 50000
GROUP BY
    ucs.UserId,
    ucs.DisplayName,
    ucs.Reputation,
    ucs.UserCreationDate,
    ucs.TotalPostsContributed,
    ucs.TotalQuestions,
    ucs.TotalAnswers,
    ucs.AverageScoreOfUserPosts,
    ucs.BadgeCount,
    ucs.GoldBadges,
    ucs.SilverBadges,
    ucs.BronzeBadges,
    ucs.LastContentEditDate
HAVING COUNT(DISTINCT ph.Id) > 5
ORDER BY ucs.Reputation DESC, ucs.UserCreationDate ASC
LIMIT 100;