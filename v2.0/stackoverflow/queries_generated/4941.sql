-- {"query": "4941.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1369} 

WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.FavoriteCount,
        p.AnswerCount,
        p.CommentCount,
        p.ClosedDate,
        pt.Name AS PostTypeName,
        u.DisplayName AS OwnerDisplayName,
        CASE
            WHEN p.PostTypeId = 1 THEN STRING_AGG(t.TagName, ',') WITHIN GROUP (ORDER BY t.TagName)
            ELSE NULL
        END AS FormattedTags,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn_user_creation,
        DENSE_RANK() OVER (ORDER BY p.Score DESC) AS dr_score,
        SUM(p.ViewCount) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running_total_views_by_user
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN (
        SELECT
            PostId,
            SUBSTRING(value, 2, LEN(value) - 2) AS TagName
        FROM Posts
        CROSS APPLY STRING_SPLIT(Tags, '><')
        WHERE PostTypeId = 1 AND Tags IS NOT NULL AND Tags <> ''
    ) t ON p.Id = t.PostId
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.CreationDate >= '2023-01-01'
    GROUP BY
        p.Id, p.PostTypeId, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, p.FavoriteCount, p.AnswerCount, p.CommentCount, p.ClosedDate, pt.Name, u.DisplayName
),
UserActivity AS (
    SELECT
        ph.UserId,
        COUNT(DISTINCT ph.PostId) AS TotalPostHistoryEntries,
        MAX(ph.CreationDate) AS LastActivityDate
    FROM PostHistory ph
    WHERE ph.CreationDate >= DATEADD(year, -1, GETDATE())
    GROUP BY ph.UserId
)
SELECT
    rp.PostId,
    rp.PostTypeName,
    rp.OwnerDisplayName,
    rp.FormattedTags,
    rp.Score,
    rp.ViewCount,
    rp.FavoriteCount,
    rp.AnswerCount,
    rp.CommentCount,
    rp.CreationDate,
    rp.ClosedDate,
    CASE WHEN rp.ClosedDate IS NOT NULL THEN 'Closed' ELSE 'Open' END AS PostStatus,
    rp.running_total_views_by_user,
    ua.TotalPostHistoryEntries,
    DATEDIFF(day, rp.CreationDate, COALESCE(rp.ClosedDate, GETDATE())) AS AgeInDays,
    CASE
        WHEN rp.Score > 100 AND rp.AnswerCount > 10 THEN 'High Engagement'
        WHEN rp.ViewCount > 10000 THEN 'High Traffic'
        WHEN rp.FavoriteCount > 50 THEN 'Popular'
        ELSE 'Standard'
    END AS PostCategory,
    (SELECT COUNT(c.Id) FROM Comments c WHERE c.PostId = rp.PostId AND c.CreationDate > rp.CreationDate) AS SubsequentCommentCount,
    (SELECT SUM(v.BountyAmount) FROM Votes v WHERE v.PostId = rp.PostId AND v.VoteTypeId = 8) AS TotalBountyAmount,
    rp.dr_score
FROM RankedPosts rp
LEFT JOIN UserActivity ua ON rp.OwnerUserId = ua.UserId
WHERE
    rp.rn_user_creation <= 5
    AND rp.Score > 0
    AND (rp.PostTypeId = 1 OR rp.PostTypeId = 2)
    AND rp.OwnerUserId IS NOT NULL
    AND rp.OwnerDisplayName LIKE '%[a-z]%'
    AND rp.FormattedTags IS NOT NULL
    AND rp.FormattedTags LIKE '%sql%'
UNION ALL
SELECT
    rp.PostId,
    rp.PostTypeName,
    rp.OwnerDisplayName,
    rp.FormattedTags,
    rp.Score,
    rp.ViewCount,
    rp.FavoriteCount,
    rp.AnswerCount,
    rp.CommentCount,
    rp.CreationDate,
    rp.ClosedDate,
    CASE WHEN rp.ClosedDate IS NOT NULL THEN 'Closed' ELSE 'Open' END AS PostStatus,
    rp.running_total_views_by_user,
    ua.TotalPostHistoryEntries,
    DATEDIFF(day, rp.CreationDate, COALESCE(rp.ClosedDate, GETDATE())) AS AgeInDays,
    CASE
        WHEN rp.Score > 100 AND rp.AnswerCount > 10 THEN 'High Engagement'
        WHEN rp.ViewCount > 10000 THEN 'High Traffic'
        WHEN rp.FavoriteCount > 50 THEN 'Popular'
        ELSE 'Standard'
    END AS PostCategory,
    (SELECT COUNT(c.Id) FROM Comments c WHERE c.PostId = rp.PostId AND c.CreationDate > rp.CreationDate) AS SubsequentCommentCount,
    (SELECT SUM(v.BountyAmount) FROM Votes v WHERE v.PostId = rp.PostId AND v.VoteTypeId = 8) AS TotalBountyAmount,
    rp.dr_score
FROM RankedPosts rp
JOIN UserActivity ua ON rp.OwnerUserId = ua.UserId
WHERE
    rp.rn_user_creation > 5
    AND rp.Score < 0
    AND rp.PostTypeId = 2
    AND rp.OwnerUserId IS NOT NULL
    AND rp.OwnerDisplayName IS NULL
    AND rp.FormattedTags IS NULL
    AND ua.TotalPostHistoryEntries > 100
ORDER BY rp.CreationDate DESC;
