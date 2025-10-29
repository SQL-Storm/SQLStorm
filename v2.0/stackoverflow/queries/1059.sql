-- {"query": "1059.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2809}
WITH ActiveTechUsers AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        COUNT(DISTINCT p.Id) AS TotalTechPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TechQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TechAnswers,
        MAX(p.LastActivityDate) AS LastTechActivityDate
    FROM Users u
    INNER JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE
        p.CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '3 years')
        AND p.PostTypeId IN (1, 2)
        AND (
            p.Tags ILIKE '%<sql>%' OR
            p.Tags ILIKE '%<database>%' OR
            p.Tags ILIKE '%<performance>%' OR
            p.Title ILIKE '%SQL%' OR
            p.Title ILIKE '%Database%' OR
            p.Title ILIKE '%Performance%'
        )
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
    HAVING COUNT(DISTINCT p.Id) >= 5
),
PostEditHistorySummary AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        COUNT(DISTINCT ph.UserId) AS DistinctEditorCount,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) AND ph.UserId = p.OwnerUserId THEN 1 ELSE 0 END) AS OwnerEditCount,
        MIN(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) AND ph.UserId = p.OwnerUserId THEN ph.CreationDate END) AS FirstOwnerEditDate,
        (
            SELECT LENGTH(ph_initial.Text)
            FROM PostHistory ph_initial
            WHERE ph_initial.PostId = p.Id AND ph_initial.PostHistoryTypeId = 2
            ORDER BY ph_initial.CreationDate
            LIMIT 1
        ) AS InitialBodyLength,
        LENGTH(p.Body) AS FinalBodyLength,
        EXTRACT(EPOCH FROM (MIN(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) AND ph.UserId = p.OwnerUserId THEN ph.CreationDate END) - p.CreationDate)) / 3600.0 AS HoursToFirstOwnerEdit
    FROM Posts p
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId
    WHERE p.PostTypeId IN (1, 2)
    GROUP BY p.Id, p.OwnerUserId, p.Body, p.CreationDate
    HAVING COUNT(DISTINCT ph.UserId) > 1 OR SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) AND ph.UserId = p.OwnerUserId THEN 1 ELSE 0 END) >= 1
),
PostEngagementMetrics AS (
    SELECT
        p.Id AS PostId,
        COUNT(DISTINCT c.Id) AS TotalComments,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS Downvotes,
        SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END) AS Favorites,
        SUM(CASE WHEN v.VoteTypeId IN (2,3) THEN 1 ELSE 0 END) AS TotalVotes,
        CASE
            WHEN SUM(CASE WHEN v.VoteTypeId IN (2,3) THEN 1 ELSE 0 END) >= 5
            THEN CAST(ABS(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) - SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END)) AS NUMERIC) / NULLIF(SUM(CASE WHEN v.VoteTypeId IN (2,3) THEN 1 ELSE 0 END), 0)
            ELSE 0.0
        END AS ControversyScore
    FROM Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId
    LEFT JOIN Comments c ON p.Id = c.PostId
    WHERE p.PostTypeId IN (1, 2)
    GROUP BY p.Id
),
UserBadgeSummary AS (
    SELECT
        b.UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
),
-- Precompute per-user controversy average to avoid window inside window definition
UserControversyAvg AS (
    SELECT
        p.OwnerUserId AS UserId,
        AVG(COALESCE(pem.ControversyScore, 0)) AS AvgControversyScore
    FROM Posts p
    INNER JOIN PostEngagementMetrics pem ON p.Id = pem.PostId
    GROUP BY p.OwnerUserId
)
SELECT
    atu.DisplayName AS UserName,
    atu.Reputation,
    atu.TotalTechPosts,
    atu.TechQuestions,
    atu.TechAnswers,
    COALESCE(ubs.GoldBadges, 0) AS UserGoldBadges,
    COALESCE(ubs.SilverBadges, 0) AS UserSilverBadges,
    COALESCE(ubs.BronzeBadges, 0) AS UserBronzeBadges,
    p.Id AS PostId,
    COALESCE(p.Title, SUBSTRING(p.Body FROM 1 FOR 50) || '...') AS PostTitleSnippet,
    p.ViewCount AS PostViewCount,
    p.CreationDate AS PostCreationDate,
    COALESCE(pem.TotalComments, 0) AS PostCommentCount,
    COALESCE(pem.Upvotes, 0) AS PostUpvotes,
    COALESCE(pem.Downvotes, 0) AS PostDownvotes,
    COALESCE(pem.Favorites, 0) AS PostFavorites,
    pem.ControversyScore AS PostControversyScore,
    peh.OwnerEditCount AS PostOwnerEditCount,
    peh.DistinctEditorCount AS PostDistinctEditorCount,
    peh.InitialBodyLength,
    peh.FinalBodyLength,
    CASE
        WHEN peh.InitialBodyLength IS NOT NULL AND peh.InitialBodyLength > 0
        THEN CAST((peh.FinalBodyLength - peh.InitialBodyLength) AS NUMERIC) / peh.InitialBodyLength * 100
        ELSE 0.0
    END AS BodyLengthChangePct,
    peh.HoursToFirstOwnerEdit,
    RANK() OVER (
        PARTITION BY FLOOR(atu.Reputation / 10000)
        ORDER BY COALESCE(uca.AvgControversyScore, 0) DESC, atu.Reputation DESC
    ) AS UserControversyRankByRepTier,
    AVG(p.Score) OVER (
        PARTITION BY p.OwnerUserId
        ORDER BY p.CreationDate
        ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ) AS MovingAvgPostScoreForUser,
    EXISTS (
        SELECT 1
        FROM PostLinks pl
        INNER JOIN Posts related_p ON pl.RelatedPostId = related_p.Id
        WHERE
            pl.PostId = p.Id
            AND pl.LinkTypeId = 3
            AND related_p.ViewCount > 50000
            AND related_p.AcceptedAnswerId IS NOT NULL
    ) AS IsDuplicateOfHighViewAcceptedPost,
    (p.Body ILIKE '%optimization%' OR p.Body ILIKE '%bottleneck%' OR p.Body ILIKE '%latency%') AS ContainsPerformanceKeywords,
    CASE
        WHEN p.ClosedDate IS NOT NULL AND p.Score > 10 AND COALESCE(pem.TotalComments, 0) > 5
        THEN 'Controversial-Closed'
        WHEN p.AcceptedAnswerId IS NOT NULL AND p.OwnerUserId = p.LastEditorUserId AND peh.OwnerEditCount > 0
        THEN 'Owner-Accepted-Refined'
        WHEN p.CommunityOwnedDate IS NOT NULL AND COALESCE(peh.DistinctEditorCount, 0) > 2
        THEN 'Community-Driven-Evolved'
        WHEN p.Score < 0 AND pem.Downvotes > pem.Upvotes * 2
        THEN 'Highly-Negative'
        ELSE 'Standard'
    END AS PostStatusCategory
FROM ActiveTechUsers atu
INNER JOIN Posts p ON atu.UserId = p.OwnerUserId
INNER JOIN PostEngagementMetrics pem ON p.Id = pem.PostId
LEFT JOIN PostEditHistorySummary peh ON p.Id = peh.PostId
LEFT JOIN UserBadgeSummary ubs ON atu.UserId = ubs.UserId
LEFT JOIN UserControversyAvg uca ON atu.UserId = uca.UserId
WHERE
    p.PostTypeId IN (1, 2)
    AND p.CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '3 years')
    AND p.ViewCount > 1000
    AND (COALESCE(peh.OwnerEditCount, 0) > 0 OR COALESCE(peh.DistinctEditorCount, 0) > 1)
    AND (
        (COALESCE(pem.Upvotes, 0) > 20 AND COALESCE(pem.Downvotes, 0) < 5 AND COALESCE(p.FavoriteCount, 0) > 3)
        OR (COALESCE(pem.ControversyScore, 0) > 0.45 AND COALESCE(pem.TotalVotes, 0) > 15 AND COALESCE(pem.TotalComments, 0) > 8)
        OR (CASE WHEN peh.InitialBodyLength IS NOT NULL AND peh.InitialBodyLength > 0 THEN CAST((peh.FinalBodyLength - peh.InitialBodyLength) AS NUMERIC) / peh.InitialBodyLength * 100 ELSE 0.0 END > 20 AND COALESCE(peh.HoursToFirstOwnerEdit, 999999) < 24)
    )
    AND EXISTS (
        SELECT 1
        FROM Badges b_sub
        WHERE b_sub.UserId = atu.UserId AND b_sub.Class IN (1, 2)
    )
ORDER BY
    atu.Reputation DESC,
    UserControversyRankByRepTier ASC,
    p.CreationDate DESC,
    pem.ControversyScore DESC;