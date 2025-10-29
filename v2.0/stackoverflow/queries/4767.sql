-- {"query": "4767.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1940}
WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        pt.Name AS PostTypeName,
        p.OwnerUserId,
        u.DisplayName AS OwnerDisplayName,
        p.CreationDate AS PostCreationDate,
        p.Score,
        p.ViewCount,
        p.CommentCount,
        p.FavoriteCount,
        p.AnswerCount,
        p.ClosedDate,
        p.CommunityOwnedDate,
        ROW_NUMBER() OVER(PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC) AS RowNumPerType,
        LAG(p.Score, 1, 0) OVER(PARTITION BY p.PostTypeId ORDER BY p.CreationDate) AS PreviousScoreForType,
        LEAD(p.ViewCount, 1, 0) OVER(PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS NextViewCountForType,
        SUM(p.Score) OVER(PARTITION BY p.PostTypeId ORDER BY p.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS RunningScoreSumForType,
        CASE
            WHEN p.ClosedDate IS NOT NULL THEN 1
            ELSE 0
        END AS IsClosedFlag,
        COALESCE(p.FavoriteCount, 0) + COALESCE(p.AnswerCount, 0) AS EngagementMetric
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.CreationDate >= TIMESTAMP '2023-01-01' AND p.CreationDate < TIMESTAMP '2024-01-01'
),
UserPostEngagement AS (
    SELECT
        rp.PostId,
        rp.PostTypeName,
        rp.OwnerUserId,
        rp.OwnerDisplayName,
        rp.PostCreationDate,
        rp.PostTypeId,
        rp.Score,
        rp.ViewCount,
        rp.CommentCount,
        rp.FavoriteCount,
        rp.AnswerCount,
        rp.EngagementMetric,
        rp.RowNumPerType,
        rp.PreviousScoreForType,
        rp.NextViewCountForType,
        rp.RunningScoreSumForType,
        rp.IsClosedFlag,
        CASE
            WHEN rp.PostTypeId = 1 THEN (SELECT COUNT(*) FROM Comments c WHERE c.PostId = rp.PostId AND c.CreationDate >= rp.PostCreationDate)
            ELSE 0
        END AS NumCommentsSinceCreation
    FROM RankedPosts rp
    WHERE rp.PostTypeId IN (1, 2)
),
PostLinkAnalysis AS (
    SELECT
        pl.PostId,
        pl.RelatedPostId,
        lt.Name AS LinkTypeName,
        pl.CreationDate AS LinkCreationDate,
        CASE
            WHEN lt.Name = 'Duplicate' THEN 1
            WHEN lt.Name = 'Linked' THEN 2
            ELSE 0
        END AS LinkTypeNumeric
    FROM PostLinks pl
    JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
    WHERE pl.CreationDate >= TIMESTAMP '2023-06-01'
),
AggregatedUserStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.Views AS UserViews,
        COUNT(p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        AVG(p.Score) AS AveragePostScore,
        MAX(p.CreationDate) AS LastPostDate
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.Id IS NOT NULL AND u.Id > 0
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views
),
PostWithAggregatedStats AS (
    SELECT
        upe.PostId,
        upe.PostTypeName,
        upe.OwnerUserId,
        upe.OwnerDisplayName,
        upe.PostCreationDate,
        upe.PostTypeId,
        upe.Score,
        upe.ViewCount,
        upe.CommentCount,
        upe.FavoriteCount,
        upe.AnswerCount,
        upe.EngagementMetric,
        upe.RowNumPerType,
        upe.PreviousScoreForType,
        upe.NextViewCountForType,
        upe.RunningScoreSumForType,
        upe.IsClosedFlag,
        upe.NumCommentsSinceCreation,
        aus.Reputation AS OwnerReputation,
        aus.TotalPosts AS OwnerTotalPosts,
        aus.QuestionCount AS OwnerQuestionCount,
        aus.AnswerCount AS OwnerAnswerCount,
        aus.AveragePostScore AS OwnerAveragePostScore,
        aus.LastPostDate AS OwnerLastPostDate,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = upe.OwnerUserId AND b.Class = 1) AS GoldBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = upe.OwnerUserId AND b.Class = 2) AS SilverBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = upe.OwnerUserId AND b.Class = 3) AS BronzeBadges,
        CASE WHEN aus.LastPostDate IS NOT NULL THEN CAST(('2024-10-01 12:34:56') AS TIMESTAMP) - aus.LastPostDate ELSE NULL END AS DaysSinceLastPost
    FROM UserPostEngagement upe
    LEFT JOIN AggregatedUserStats aus ON upe.OwnerUserId = aus.UserId
    LEFT JOIN Users u ON upe.OwnerUserId = u.Id
)
SELECT
    p.PostId,
    p.PostTypeName,
    p.OwnerUserId,
    p.OwnerDisplayName,
    p.PostCreationDate,
    p.Score,
    p.ViewCount,
    p.CommentCount,
    p.FavoriteCount,
    p.AnswerCount,
    p.EngagementMetric,
    p.RowNumPerType,
    p.PreviousScoreForType,
    p.NextViewCountForType,
    p.RunningScoreSumForType,
    p.IsClosedFlag,
    p.NumCommentsSinceCreation,
    p.OwnerReputation,
    p.OwnerTotalPosts,
    p.OwnerQuestionCount,
    p.OwnerAnswerCount,
    p.OwnerAveragePostScore,
    p.OwnerLastPostDate,
    p.GoldBadges,
    p.SilverBadges,
    p.BronzeBadges,
    p.DaysSinceLastPost,
    COALESCE(pla.LinkTypeName, 'No Links') AS PrimaryLinkType,
    CASE
        WHEN pla.LinkTypeNumeric = 1 THEN 'Duplicate'
        WHEN pla.LinkTypeNumeric = 2 THEN 'Linked'
        ELSE 'Other'
    END AS LinkStatusCategory,
    (
        SELECT COUNT(*)
        FROM PostHistory ph
        WHERE ph.PostId = p.PostId
        AND ph.PostHistoryTypeId IN (4, 5, 6)
    ) AS EditCount,
    (
        SELECT ph2.UserDisplayName
        FROM PostHistory ph2
        WHERE ph2.PostId = p.PostId
        AND ph2.PostHistoryTypeId IN (4, 5, 6)
        ORDER BY ph2.CreationDate DESC
        LIMIT 1
    ) AS LastEditorDisplayName,
    (
        SELECT ph3.CreationDate
        FROM PostHistory ph3
        WHERE ph3.PostId = p.PostId
        AND ph3.PostHistoryTypeId IN (4, 5, 6)
        ORDER BY ph3.CreationDate DESC
        LIMIT 1
    ) AS LastEditDateFromHistory,
    CASE
        WHEN p.PostCreationDate < (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year') AND p.IsClosedFlag = 0 AND COALESCE(p.OwnerReputation,0) < 1000 THEN 'Potentially Stale'
        WHEN p.PostCreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year') AND p.IsClosedFlag = 1 THEN 'Recently Closed'
        WHEN p.EngagementMetric > 500 AND p.IsClosedFlag = 0 THEN 'Highly Engaged'
        ELSE 'Standard'
    END AS PostStatusCategory,
    (COALESCE(p.OwnerDisplayName, '') || ' (' || COALESCE(CAST(p.OwnerReputation AS VARCHAR), '0') || ')') AS OwnerInfoString,
    ROW_NUMBER() OVER (ORDER BY p.Score DESC, p.ViewCount DESC) AS GlobalRank
FROM PostWithAggregatedStats p
LEFT JOIN PostLinkAnalysis pla ON p.PostId = pla.PostId
WHERE p.Score > 5 OR p.ViewCount > 1000
ORDER BY p.PostCreationDate DESC
LIMIT 100;