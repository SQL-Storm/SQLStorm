WITH RecentPosts AS (
    SELECT 
        p.Id, 
        p.Title, 
        p.CreationDate, 
        p.Score, 
        p.ViewCount, 
        p.AnswerCount, 
        u.DisplayName AS OwnerDisplayName, 
        u.Reputation,
        COALESCE(SUM(v.BountyAmount), 0) AS TotalBounty,
        p.OwnerUserId
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId IN (8, 9)
    WHERE p.CreationDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 month'
    GROUP BY p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, u.DisplayName, u.Reputation, p.OwnerUserId
),
PostActivity AS (
    SELECT 
        p.Id, 
        COUNT(DISTINCT ph.Id) AS EditCount,
        COUNT(DISTINCT c.Id) AS CommentCount
    FROM Posts p
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId
    LEFT JOIN Comments c ON p.Id = c.PostId
    GROUP BY p.Id
),
TopUsers AS (
    SELECT 
        u.Id, 
        u.DisplayName, 
        COUNT(DISTINCT p.Id) AS TotalPosts, 
        SUM(p.Score) AS TotalScore, 
        SUM(p.ViewCount) AS TotalViews, 
        SUM(p.AnswerCount) AS TotalAnswers
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY u.Id, u.DisplayName
    HAVING COUNT(DISTINCT p.Id) > 10
),
PostTags AS (
    SELECT 
        p.Id,
        STRING_AGG(t.TagName, ', ') AS tagNames
    FROM Posts p
    JOIN Tags t ON p.Id = t.ExcerptPostId
    GROUP BY p.Id
)
SELECT 
    rp.Id AS PostId,
    rp.Title,
    rp.CreationDate,
    rp.Score,
    rp.ViewCount,
    rp.AnswerCount,
    rp.OwnerDisplayName,
    rp.Reputation,
    rp.TotalBounty,
    pa.EditCount,
    pa.CommentCount,
    pt.tagNames,
    tu.DisplayName AS TopUserDisplayName,
    tu.TotalPosts,
    tu.TotalScore,
    tu.TotalViews,
    tu.TotalAnswers
FROM RecentPosts rp
JOIN PostActivity pa ON rp.Id = pa.Id
JOIN PostTags pt ON rp.Id = pt.Id
LEFT JOIN TopUsers tu ON rp.OwnerUserId = tu.Id
ORDER BY rp.CreationDate DESC, rp.Score DESC
LIMIT 100;