WITH TopAnswerers AS (
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(*) AS AnswerCount,
        AVG(p.Score) AS AvgAnswerScore,
        SUM(p.Score) AS TotalScore
    FROM
        Posts p
    WHERE
        p.PostTypeId = 2
        AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year'
        AND p.OwnerUserId IS NOT NULL
    GROUP BY
        p.OwnerUserId
    HAVING
        COUNT(*) > 50
),
ActiveBadgeWinners AS (
    SELECT
        u.Id AS UserId,
        COUNT(*) AS RecentBadges
    FROM
        Users u
        JOIN Badges b ON b.UserId = u.Id
    WHERE
        b.Date >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '6 months'
    GROUP BY
        u.Id
),
MostDiscussedAnswers AS (
    SELECT
        c.PostId,
        COUNT(*) AS CommentCount
    FROM
        Comments c
        JOIN Posts p ON c.PostId = p.Id
    WHERE
        p.PostTypeId = 2
        AND c.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year'
    GROUP BY
        c.PostId
    HAVING
        COUNT(*) > 10
),
AwardedAcceptedAnswers AS (
    SELECT
        a.OwnerUserId AS UserId,
        COUNT(DISTINCT a.Id) AS AcceptedAnswers
    FROM
        Posts q
        JOIN Posts a ON q.AcceptedAnswerId = a.Id
    WHERE
        q.PostTypeId = 1
        AND a.PostTypeId = 2
        AND a.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year'
    GROUP BY
        a.OwnerUserId
),
HighReputationUsers AS (
    SELECT
        Id AS UserId,
        Reputation
    FROM
        Users
    WHERE
        Reputation >= 10000
)
SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COALESCE(ta.AnswerCount, 0) AS AnswersThisYear,
    COALESCE(ta.TotalScore, 0) AS AnswerScoreThisYear,
    COALESCE(ta.AvgAnswerScore, 0) AS AvgAnswerScoreThisYear,
    COALESCE(abw.RecentBadges, 0) AS BadgesLast6M,
    COALESCE(aaa.AcceptedAnswers, 0) AS AcceptedAnswersThisYear,
    COUNT(DISTINCT mda.PostId) AS AnswersWith10plusComments,
    COUNT(DISTINCT b.Id) AS TotalBadges
FROM
    Users u
    INNER JOIN HighReputationUsers hru ON hru.UserId = u.Id
    LEFT JOIN TopAnswerers ta ON ta.UserId = u.Id
    LEFT JOIN ActiveBadgeWinners abw ON abw.UserId = u.Id
    LEFT JOIN AwardedAcceptedAnswers aaa ON aaa.UserId = u.Id
    LEFT JOIN (
        SELECT mda_inner.PostId, p_inner.OwnerUserId
        FROM MostDiscussedAnswers mda_inner
        JOIN Posts p_inner ON p_inner.Id = mda_inner.PostId
    ) mda ON mda.OwnerUserId = u.Id
    LEFT JOIN Badges b ON b.UserId = u.Id
WHERE
    (COALESCE(ta.AnswerCount, 0) > 0 OR COALESCE(abw.RecentBadges, 0) > 0 OR COALESCE(aaa.AcceptedAnswers, 0) > 0)
GROUP BY
    u.Id,
    u.DisplayName,
    u.Reputation,
    ta.AnswerCount,
    ta.TotalScore,
    ta.AvgAnswerScore,
    abw.RecentBadges,
    aaa.AcceptedAnswers
ORDER BY
    ta.TotalScore DESC,
    abw.RecentBadges DESC,
    aaa.AcceptedAnswers DESC
LIMIT 50;