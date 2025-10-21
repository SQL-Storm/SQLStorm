-- {"query": "35047.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 691} 
WITH TopUsersByAcceptedAnswers AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(pa.Id) AS AcceptedAnswerCount
    FROM Users u
    JOIN Posts pa ON pa.OwnerUserId = u.Id
    WHERE pa.PostTypeId = 2
      AND pa.Id IN (SELECT p.AcceptedAnswerId FROM Posts p WHERE p.AcceptedAnswerId IS NOT NULL)
    GROUP BY u.Id, u.DisplayName, u.Reputation
    ORDER BY AcceptedAnswerCount DESC
    LIMIT 50
),
UserBadgeStats AS (
    SELECT
        b.UserId,
        COUNT(*) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges b
    WHERE b.UserId IN (SELECT UserId FROM TopUsersByAcceptedAnswers)
    GROUP BY b.UserId
),
UserCommentStats AS (
    SELECT
        c.UserId,
        COUNT(*) AS CommentCount,
        AVG(c.Score) AS AvgCommentScore
    FROM Comments c
    WHERE c.UserId IN (SELECT UserId FROM TopUsersByAcceptedAnswers)
    GROUP BY c.UserId
),
UserPostHistoryEdits AS (
    SELECT
        ph.UserId,
        COUNT(*) AS EditCount
    FROM PostHistory ph
    WHERE ph.UserId IN (SELECT UserId FROM TopUsersByAcceptedAnswers)
      AND ph.PostHistoryTypeId IN (4, 5, 6) -- Title, Body, Tag edits
    GROUP BY ph.UserId
),
UserRecentActivity AS (
    SELECT
        p.OwnerUserId AS UserId,
        MAX(p.LastActivityDate) AS LastActivityDate
    FROM Posts p
    WHERE p.OwnerUserId IN (SELECT UserId FROM TopUsersByAcceptedAnswers)
    GROUP BY p.OwnerUserId
)
SELECT
    tu.UserId,
    tu.DisplayName,
    tu.Reputation,
    tu.AcceptedAnswerCount,
    COALESCE(ub.TotalBadges, 0) AS TotalBadges,
    COALESCE(ub.GoldBadges, 0) AS GoldBadges,
    COALESCE(ub.SilverBadges, 0) AS SilverBadges,
    COALESCE(ub.BronzeBadges, 0) AS BronzeBadges,
    COALESCE(uc.CommentCount, 0) AS CommentCount,
    COALESCE(uc.AvgCommentScore, 0) AS AvgCommentScore,
    COALESCE(uphe.EditCount, 0) AS EditCount,
    COALESCE(ur.LastActivityDate, NULL) AS LastActivityDate
FROM TopUsersByAcceptedAnswers tu
LEFT JOIN UserBadgeStats ub ON tu.UserId = ub.UserId
LEFT JOIN UserCommentStats uc ON tu.UserId = uc.UserId
LEFT JOIN UserPostHistoryEdits uphe ON tu.UserId = uphe.UserId
LEFT JOIN UserRecentActivity ur ON tu.UserId = ur.UserId
ORDER BY tu.AcceptedAnswerCount DESC, tu.Reputation DESC;