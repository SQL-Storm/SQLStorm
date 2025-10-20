-- {"query": "23047.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2685, "output_tokens": 816} 
WITH TopQuestions AS (
    SELECT 
        p.Id AS QuestionId,
        p.Title,
        p.ViewCount,
        p.OwnerUserId,
        ROW_NUMBER() OVER (ORDER BY p.ViewCount DESC) AS ViewRank,
        COALESCE(p.FavoriteCount, 0) AS FavCount
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.ViewCount > 1000
),
UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        MAX(b.Date) AS LatestBadgeDate
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(DISTINCT b.Id) > 5
),
PostActivity AS (
    SELECT 
        ph.PostId,
        COUNT(ph.Id) AS EditCount,
        MAX(ph.CreationDate) AS LastEdit,
        STRING_AGG(COALESCE(ph.UserDisplayName, 'Anonymous'), ', ') AS Editors
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4,5,6,7,8,9)  -- Edits and rollbacks
    GROUP BY ph.PostId
),
CombinedData AS (
    SELECT 
        tq.QuestionId,
        tq.Title,
        tq.ViewCount,
        tq.ViewRank,
        us.DisplayName AS OwnerName,
        us.Reputation,
        us.BadgeCount,
        us.GoldBadges,
        pa.EditCount,
        pa.LastEdit,
        pa.Editors,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = tq.QuestionId AND c.Score > 0) AS PositiveComments,
        COALESCE(NULLIF(tq.FavCount, 0), (SELECT AVG(FavoriteCount) FROM Posts WHERE PostTypeId = 1)) AS AdjustedFavs,
        CASE 
            WHEN tq.ViewCount > 10000 THEN 'High Views'
            WHEN tq.ViewCount BETWEEN 5000 AND 10000 THEN 'Medium Views'
            ELSE 'Low Views'
        END AS ViewCategory
    FROM TopQuestions tq
    INNER JOIN UserStats us ON tq.OwnerUserId = us.UserId
    LEFT OUTER JOIN PostActivity pa ON tq.QuestionId = pa.PostId
    WHERE us.Reputation > 1000
      AND EXISTS (SELECT 1 FROM Votes v WHERE v.PostId = tq.QuestionId AND v.VoteTypeId = 2)  -- Has upvotes
)
SELECT 
    cd.QuestionId,
    cd.Title,
    cd.ViewCount,
    cd.ViewRank,
    cd.OwnerName,
    cd.Reputation,
    cd.BadgeCount,
    cd.GoldBadges,
    cd.EditCount,
    cd.LastEdit,
    cd.Editors,
    cd.PositiveComments,
    cd.AdjustedFavs,
    cd.ViewCategory,
    RANK() OVER (PARTITION BY cd.ViewCategory ORDER BY cd.Reputation DESC) AS CategoryRank
FROM CombinedData cd
UNION ALL
SELECT 
    NULL AS QuestionId,
    'Summary' AS Title,
    SUM(ViewCount) AS ViewCount,
    NULL AS ViewRank,
    NULL AS OwnerName,
    AVG(Reputation) AS Reputation,
    SUM(BadgeCount) AS BadgeCount,
    SUM(GoldBadges) AS GoldBadges,
    AVG(EditCount) AS EditCount,
    MAX(LastEdit) AS LastEdit,
    NULL AS Editors,
    SUM(PositiveComments) AS PositiveComments,
    AVG(AdjustedFavs) AS AdjustedFavs,
    'All' AS ViewCategory,
    NULL AS CategoryRank
FROM CombinedData
ORDER BY ViewRank ASC, CategoryRank ASC;