-- {"query": "4962.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1589} 

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
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        p.CommunityOwnedDate,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC) AS rn,
        COUNT(c.Id) OVER (PARTITION BY p.Id) AS CommentCountPerPost,
        SUM(v.VoteTypeId) OVER (PARTITION BY p.Id) AS TotalVoteValuePerPost,
        LAG(p.Score, 1, 0) OVER (ORDER BY p.CreationDate) AS PreviousPostScore,
        LEAD(p.Score, 1, 0) OVER (ORDER BY p.CreationDate) AS NextPostScore,
        CASE
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
            WHEN p.FavoriteCount > 1000 THEN 'Highly Favorited'
            ELSE 'Active'
        END AS PostStatusCategory
    FROM Posts AS p
    LEFT JOIN PostTypes AS pt ON p.PostTypeId = pt.Id
    LEFT JOIN Users AS u ON p.OwnerUserId = u.Id
    LEFT JOIN Comments AS c ON p.Id = c.PostId
    LEFT JOIN Votes AS v ON p.Id = v.PostId
    WHERE p.OwnerUserId IS NOT NULL AND p.CreationDate > '2023-01-01'
    GROUP BY
        p.Id, p.PostTypeId, pt.Name, p.OwnerUserId, u.DisplayName, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, p.FavoriteCount, p.ClosedDate, p.CommunityOwnedDate
),
TagAnalysis AS (
    SELECT
        p.Id AS PostId,
        t.TagName,
        COUNT(pl.Id) AS LinkCount,
        CASE
            WHEN t.IsModeratorOnly = 1 THEN 'ModeratorOnly'
            WHEN t.IsRequired = 1 THEN 'Required'
            ELSE 'Standard'
        END AS TagCategory
    FROM Posts AS p
    JOIN Tags AS t ON LOWER(t.TagName) = ANY(string_to_array(REPLACE(REPLACE(p.Tags, '<', ''), '>', ''), ' '))
    LEFT JOIN PostLinks AS pl ON p.Id = pl.PostId OR p.Id = pl.RelatedPostId
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL AND p.Tags <> ''
    GROUP BY p.Id, t.TagName, TagCategory
),
UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS UserPostCount,
        AVG(p.Score) AS AvgUserPostScore,
        SUM(CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END) AS UserClosedPostCount,
        MAX(p.CreationDate) AS LastPostDate
    FROM Users AS u
    JOIN Posts AS p ON u.Id = p.OwnerUserId
    WHERE u.Reputation > 5000 AND u.CreationDate < '2023-01-01'
    GROUP BY u.Id, u.DisplayName
),
CommentQuality AS (
    SELECT
        c.PostId,
        AVG(c.Score) AS AvgCommentScore,
        COUNT(CASE WHEN c.UserDisplayName IS NULL THEN 1 ELSE NULL END) AS AnonymousCommentCount,
        STRING_AGG(c.Text, ' | ' ORDER BY c.CreationDate) AS AllCommentTexts
    FROM Comments AS c
    WHERE c.CreationDate > '2023-01-01'
    GROUP BY c.PostId
)
SELECT
    rp.PostId,
    rp.PostTypeName,
    rp.OwnerDisplayName,
    rp.PostCreationDate,
    rp.Score,
    rp.ViewCount,
    rp.CommentCount,
    rp.FavoriteCount,
    rp.rn AS RankByType,
    rp.CommentCountPerPost,
    rp.TotalVoteValuePerPost,
    rp.PreviousPostScore,
    rp.NextPostScore,
    rp.PostStatusCategory,
    COALESCE(ta.TagName, 'N/A') AS PrimaryTag,
    ta.TagCategory,
    COALESCE(ua.UserPostCount, 0) AS UserTotalPosts,
    COALESCE(ua.AvgUserPostScore, 0.0) AS UserAvgScore,
    ua.UserClosedPostCount,
    ua.LastPostDate,
    cq.AvgCommentScore,
    cq.AnonymousCommentCount,
    CASE WHEN cq.AllCommentTexts IS NULL THEN 'No Comments' ELSE 'Comments Present' END AS HasComments,
    UPPER(rp.PostTypeName || '-' || COALESCE(ta.TagName, 'NULL')) AS CompositeKey,
    rp.Score + rp.ViewCount * 0.1 + rp.FavoriteCount * 0.5 AS PerformanceScore,
    CASE
        WHEN rp.Score > 100 AND rp.ViewCount > 10000 THEN 'High Performance Question'
        WHEN rp.PostTypeId = 2 AND rp.Score > 50 THEN 'Highly Scored Answer'
        ELSE 'Standard Post'
    END AS PostClassification,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = rp.PostId AND ph.PostHistoryTypeId IN (4, 5, 6)) AS EditHistoryCount,
    EXISTS (SELECT 1 FROM PostLinks pl WHERE pl.PostId = rp.PostId AND pl.LinkTypeId = 3) AS IsDuplicateLink,
    rp.PostCreationDate BETWEEN '2023-01-01' AND '2023-12-31' AS WasPostedIn2023
FROM RankedPosts AS rp
LEFT JOIN TagAnalysis AS ta ON rp.PostId = ta.PostId AND ta.rn = 1 -- Assuming we want the 'most relevant' tag if multiple
LEFT JOIN UserActivity AS ua ON rp.OwnerUserId = ua.UserId
LEFT JOIN CommentQuality AS cq ON rp.PostId = cq.PostId
WHERE rp.PostTypeId IN (1, 2) -- Focusing on Questions and Answers
  AND rp.Score >= 0 -- Ensure non-negative scores
  AND (rp.ClosedDate IS NULL OR rp.ClosedDate > NOW() - INTERVAL '1 year') -- Consider only recently active or never closed
ORDER BY rp.Score DESC, rp.ViewCount DESC
LIMIT 100;
