-- {"query": "13019.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2142, "output_tokens": 834} 

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
        u.LastAccessDate > NOW() - INTERVAL '1 year'
        AND u.Reputation > 1000
    GROUP BY 
        u.Id
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
        ph.CreationDate AS LastEditDate,
        STRING_AGG(DISTINCT t.TagName, ', ') AS Tags
    FROM 
        Posts p
    CROSS APPLY (
        SELECT TOP 1 ph.CreationDate
        FROM PostHistory ph
        WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (4, 5, 6)
        ORDER BY ph.CreationDate DESC
    ) ph
    LEFT JOIN 
        Tags t ON p.Tags LIKE CONCAT('%<', t.TagName, '>%')
    WHERE 
        p.PostTypeId = 1
        AND p.ClosedDate IS NULL
    GROUP BY 
        p.Id, p.Title, p.Score, p.ViewCount, p.CreationDate, ph.CreationDate
), FinalReport AS (
    SELECT 
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
    ROUND((fr.Score::DECIMAL / NULLIF(fr.ViewCount, 1)) * 100, 2) AS EngagementRate
FROM 
    FinalReport fr
ORDER BY 
    fr.TotalBountyEarned DESC, fr.Score DESC;
