WITH UserMetrics AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS AccountCreationDate,
        EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - u.CreationDate)) / 86400.0 AS AccountAgeDays,
        COUNT(b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        (SELECT COUNT(*) FROM Posts p_q WHERE p_q.OwnerUserId = u.Id AND p_q.PostTypeId = 1) AS QuestionCount,
        (SELECT COUNT(*) FROM Posts p_a WHERE p_a.OwnerUserId = u.Id AND p_a.PostTypeId = 2) AS AnswerCount
    FROM
        Users u
    LEFT JOIN
        Badges b ON u.Id = b.UserId
    WHERE
        u.Reputation > 1500 AND u.Id > 0
    GROUP BY
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate
    HAVING
        COUNT(b.Id) > 10
),
PostPerformance AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.FavoriteCount,
        p.CreationDate,
        p.Tags,
        p.AnswerCount AS PostAnswerCount,
        p.LastEditDate,
        COALESCE(p.ViewCount, 1) AS SafeViewCount,
        p.CreationDate - LAG(p.CreationDate, 1, p.CreationDate) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS TimeSinceLastPost,
        (SELECT MIN(a.CreationDate) FROM Posts a WHERE a.ParentId = p.Id) AS FirstAnswerDate,
        (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (4, 5, 6)) AS EditCount
    FROM
        Posts p
    WHERE p.CommunityOwnedDate IS NULL AND p.ClosedDate IS NULL AND p.OwnerUserId IN (SELECT UserId FROM UserMetrics)
),
UserContributionSummary AS (
    SELECT
        um.UserId,
        um.DisplayName,
        um.Reputation,
        um.AccountAgeDays,
        um.GoldBadges,
        um.SilverBadges,
        um.BronzeBadges,
        um.QuestionCount,
        um.AnswerCount,
        pp.PostId,
        pt.Name AS PostType,
        pp.Score,
        pp.SafeViewCount,
        pp.FavoriteCount,
        pp.PostAnswerCount,
        pp.EditCount,
        pp.TimeSinceLastPost,
        CASE
            WHEN pp.PostTypeId = 1 THEN EXTRACT(EPOCH FROM (pp.FirstAnswerDate - pp.CreationDate)) / 60.0
            ELSE NULL
        END AS MinsToFirstAnswer,
        CAST(pp.Score AS DECIMAL) / NULLIF(pp.SafeViewCount, 0) AS ScorePerView,
        AVG(pp.Score) OVER (PARTITION BY um.UserId, pp.PostTypeId) AS AvgScoreForPostType,
        DENSE_RANK() OVER (PARTITION BY um.UserId ORDER BY pp.Score DESC, pp.CreationDate DESC) AS UserPostRank
    FROM
        UserMetrics um
    JOIN
        PostPerformance pp ON um.UserId = pp.OwnerUserId
    JOIN
        PostTypes pt ON pp.PostTypeId = pt.Id
    WHERE pp.Score > 0
)
SELECT
    ucs.DisplayName,
    ucs.Reputation,
    ucs.UserPostRank,
    ucs.PostType,
    ucs.Score,
    ucs.AvgScoreForPostType,
    (ucs.Score - ucs.AvgScoreForPostType) AS ScoreDelta,
    CASE
        WHEN (ucs.Reputation / (ucs.AccountAgeDays + 1)) > 50 AND ucs.GoldBadges > 5 THEN 'Power User'
        WHEN ucs.QuestionCount > ucs.AnswerCount * 1.5 THEN 'Question Asker'
        WHEN ucs.AnswerCount > ucs.QuestionCount * 1.5 THEN 'Answer Provider'
        ELSE 'Balanced Contributor'
    END AS UserProfile,
    ucs.MinsToFirstAnswer,
    ucs.TimeSinceLastPost,
    REVERSE(SUBSTRING(REVERSE(LOWER(u.Location)), 1, 15)) AS PartialReversedLocation,
    (SELECT crt.Name
     FROM PostHistory ph_close
     JOIN CloseReasonTypes crt ON CAST(ph_close.Comment AS INTEGER) = crt.Id
     WHERE ph_close.PostId = p_main.Id AND ph_close.PostHistoryTypeId = 10
     ORDER BY ph_close.CreationDate DESC FETCH FIRST 1 ROW ONLY) AS LastCloseReason
FROM
    UserContributionSummary ucs
JOIN
    Users u ON ucs.UserId = u.Id
JOIN
    Posts p_main ON ucs.PostId = p_main.Id
WHERE
    ucs.UserPostRank <= 3

UNION ALL

SELECT
    u.DisplayName,
    u.Reputation,
    0 AS UserPostRank,
    'Voter' AS PostType,
    v.VoteTypeId AS Score,
    (SELECT AVG(p2.Score) FROM Posts p2 WHERE p2.Id IN (SELECT vt.PostId FROM Votes vt WHERE vt.UserId = u.Id)) AS AvgScoreForPostType,
    0 AS ScoreDelta,
    'Specialist Voter' AS UserProfile,
    NULL AS MinsToFirstAnswer,
    NULL AS TimeSinceLastPost,
    NULL AS PartialReversedLocation,
    NULL AS LastCloseReason
FROM
    Users u
JOIN
    Votes v ON u.Id = v.UserId
WHERE
    v.VoteTypeId = 8
    AND u.Id IN (
        SELECT DISTINCT UserId FROM Badges WHERE Name IN ('Altruist', 'Benefactor', 'Investor')
    )
ORDER BY
    Reputation DESC,
    DisplayName,
    UserPostRank
FETCH FIRST 1000 ROWS ONLY;