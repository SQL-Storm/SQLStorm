WITH UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS PostsCount,
        SUM(CASE WHEN p.Score > 10 THEN 1 ELSE 0 END) AS HighScorePosts,
        MAX(p.CreationDate) AS LastPostDate,
        SUM(COALESCE(v.BountyAmount, 0)) AS TotalBountyEarned
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN 
        Votes v ON p.Id = v.PostId AND v.VoteTypeId = 8
    WHERE 
        u.LastAccessDate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1' YEAR)
        AND u.Reputation > 1000
    GROUP BY 
        u.Id, u.DisplayName, u.Reputation
), TopUsers AS (
    SELECT 
        UserId,
        DisplayName,
        Reputation,
        PostsCount,
        HighScorePosts,
        LastPostDate,
        TotalBountyEarned,
        RANK() OVER (ORDER BY TotalBountyEarned DESC) AS BountyRank
    FROM 
        UserActivity
), PostAnalytics AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        ph.LastEditDate,
        STRING_AGG(DISTINCT t.TagName, ', ') AS Tags
    FROM 
        Posts p
    LEFT JOIN LATERAL (
        SELECT ph2.CreationDate AS LastEditDate
        FROM PostHistory ph2
        WHERE ph2.PostId = p.Id AND ph2.PostHistoryTypeId IN (4, 5, 6)
        ORDER BY ph2.CreationDate DESC
        LIMIT 1
    ) ph ON TRUE
    LEFT JOIN 
        Tags t ON p.Tags LIKE '%' || '<' || t.TagName || '>' || '%'
    WHERE 
        p.PostTypeId = 1
        AND p.ClosedDate IS NULL
    GROUP BY 
        p.Id, p.Title, p.Score, p.ViewCount, p.CreationDate, ph.LastEditDate
), FinalReport AS (
    SELECT 
        tu.UserId,
        tu.DisplayName,
        tu.Reputation,
        tu.PostsCount,
        tu.HighScorePosts,
        tu.LastPostDate,
        tu.TotalBountyEarned,
        pa.PostId,
        pa.Title,
        pa.Score,
        pa.ViewCount,
        pa.CreationDate,
        pa.LastEditDate,
        pa.Tags
    FROM 
        TopUsers tu
    JOIN 
        PostAnalytics pa ON tu.UserId = pa.PostId
    WHERE 
        tu.BountyRank <= 10
)
SELECT 
    fr.DisplayName,
    fr.Reputation,
    fr.PostsCount,
    fr.HighScorePosts,
    fr.LastPostDate,
    fr.TotalBountyEarned,
    fr.PostId,
    fr.Title,
    fr.Score,
    fr.ViewCount,
    fr.CreationDate,
    fr.LastEditDate,
    fr.Tags,
    ROUND((CAST(fr.Score AS DECIMAL) / NULLIF(fr.ViewCount, 0)) * 100, 2) AS EngagementRate
FROM 
    FinalReport fr
ORDER BY 
    fr.TotalBountyEarned DESC, fr.Score DESC;