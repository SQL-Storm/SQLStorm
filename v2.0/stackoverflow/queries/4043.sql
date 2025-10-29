WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        pt.Name AS PostTypeName,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn_desc,
        RANK() OVER (ORDER BY p.Score DESC) AS rnk_score,
        p.ViewCount
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    WHERE p.Score > 10
),
UserEngagement AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        COUNT(DISTINCT c.Id) AS CommentCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
        COUNT(DISTINCT b.Id) AS BadgeCount
    FROM Users u
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate < (cast('2024-10-01' as date) - INTERVAL '1 year')
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location
    HAVING u.Reputation > 5000 OR COUNT(DISTINCT c.Id) > 50
),
HighScoringAnswers AS (
    SELECT
        pr.ParentId,
        COUNT(pr.Id) AS HighScoringAnswerCount,
        AVG(pr.Score) AS AvgHighScoringAnswerScore
    FROM Posts pr
    WHERE pr.PostTypeId = 2 AND pr.Score > 5
    GROUP BY pr.ParentId
)
SELECT
    rp.PostId,
    rp.Title,
    rp.PostTypeName,
    ue.DisplayName AS OwnerDisplayName,
    ue.Reputation,
    ue.CommentCount,
    ue.UpVoteCount,
    ue.DownVoteCount,
    ue.BadgeCount,
    hsa.HighScoringAnswerCount,
    hsa.AvgHighScoringAnswerScore,
    CASE
        WHEN rp.rn_desc <= 5 THEN 'Recent High Scorer'
        WHEN rp.rnk_score <= 100 THEN 'Top Rated Post'
        ELSE 'Other'
    END AS PostCategory,
    CHAR_LENGTH(rp.Title) AS TitleLength,
    COALESCE(rp.ViewCount, 0) AS Views,
    CASE WHEN rp.OwnerUserId IS NULL THEN 'Community Owned' ELSE 'User Owned' END AS OwnershipType,
    rp.CreationDate AS PostCreationDate,
    ue.CreationDate AS UserCreationDate
FROM RankedPosts rp
JOIN UserEngagement ue ON rp.OwnerUserId = ue.UserId
LEFT JOIN HighScoringAnswers hsa ON rp.PostId = hsa.ParentId
WHERE rp.PostTypeName = 'Question'
  AND rp.Score > (
      SELECT AVG(p2.Score)
      FROM Posts p2
      JOIN PostTypes pt2 ON p2.PostTypeId = pt2.Id
      WHERE pt2.Name = 'Question'
  )
  AND ue.DisplayName IS NOT NULL
  AND ue.DisplayName LIKE 'A%'
  AND COALESCE(ue.Location, 'Unknown') <> 'Unknown'
UNION ALL
SELECT
    rp.PostId,
    rp.Title,
    rp.PostTypeName,
    ue.DisplayName AS OwnerDisplayName,
    ue.Reputation,
    ue.CommentCount,
    ue.UpVoteCount,
    ue.DownVoteCount,
    ue.BadgeCount,
    hsa.HighScoringAnswerCount,
    hsa.AvgHighScoringAnswerScore,
    CASE
        WHEN rp.rn_desc <= 5 THEN 'Recent High Scorer'
        WHEN rp.rnk_score <= 100 THEN 'Top Rated Post'
        ELSE 'Other'
    END AS PostCategory,
    CHAR_LENGTH(rp.Title) AS TitleLength,
    COALESCE(rp.ViewCount, 0) AS Views,
    CASE WHEN rp.OwnerUserId IS NULL THEN 'Community Owned' ELSE 'User Owned' END AS OwnershipType,
    rp.CreationDate AS PostCreationDate,
    ue.CreationDate AS UserCreationDate
FROM RankedPosts rp
JOIN UserEngagement ue ON rp.OwnerUserId = ue.UserId
LEFT JOIN HighScoringAnswers hsa ON rp.PostId = hsa.ParentId
WHERE rp.PostTypeName = 'Answer'
  AND rp.Score > 1
  AND ue.Reputation BETWEEN 1000 AND 10000
ORDER BY PostCreationDate DESC
LIMIT 50;