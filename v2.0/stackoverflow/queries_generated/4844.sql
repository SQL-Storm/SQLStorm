-- {"query": "4844.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 832} 
WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CommentCount,
        p.AnswerCount,
        ROW_NUMBER() OVER (ORDER BY p.Score DESC, p.ViewCount DESC) AS ScoreRank,
        ROW_NUMBER() OVER (ORDER BY p.ViewCount DESC, p.Score DESC) AS ViewRank,
        AVG(CAST(p.AnswerCount AS FLOAT)) OVER (PARTITION BY p.PostTypeId) AS AvgAnswerCountForType
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) AND p.Score > 0 AND p.OwnerUserId IS NOT NULL
),
UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT ph.PostId) AS PostHistoryCount,
        SUM(CASE WHEN ph.PostHistoryTypeId = 2 THEN 1 ELSE 0 END) AS BodyEdits,
        MAX(u.Reputation) AS MaxUserReputation
    FROM Users u
    JOIN PostHistory ph ON u.Id = ph.UserId
    WHERE ph.CreationDate >= DATE('now', '-1 year')
    GROUP BY u.Id, u.DisplayName
    HAVING COUNT(DISTINCT ph.PostId) > 5
),
TagContributions AS (
    SELECT
        rp.PostId,
        STRING_AGG(t.TagName, ', ') AS Tags,
        COUNT(DISTINCT u.Id) AS DistinctUsersContributingToTags
    FROM RankedPosts rp
    LEFT JOIN Tags t ON rp.Tags LIKE '%' || t.TagName || '%'
    LEFT JOIN Posts p_tag ON t.Id = p_tag.Tags::int -- Assuming Tags column can be cast to int for joined post
    LEFT JOIN PostHistory ph ON p_tag.Id = ph.PostId AND ph.PostHistoryTypeId IN (3, 6, 9)
    LEFT JOIN Users u ON ph.UserId = u.Id
    GROUP BY rp.PostId
    HAVING COUNT(DISTINCT t.TagName) > 1
)
SELECT
    rp.PostId,
    rp.Title,
    rp.Score,
    rp.ViewCount,
    rp.CommentCount,
    rp.AnswerCount,
    rp.ScoreRank,
    rp.ViewRank,
    rp.AvgAnswerCountForType,
    ua.DisplayName AS TopContributor,
    tc.Tags AS ContributingTags,
    tc.DistinctUsersContributingToTags,
    CASE
        WHEN rp.Score > ua.MaxUserReputation * 0.5 THEN 'High Score Relative to Contributor'
        WHEN rp.ViewCount > rp.AvgAnswerCountForType * 10 THEN 'High View Count'
        ELSE 'Standard Performance'
    END AS PerformanceCategory,
    COALESCE(rp.AnswerCount, 0) + COALESCE(rp.CommentCount, 0) AS TotalInteractions,
    CASE WHEN rp.Score > 1000 THEN 'Very High Score' WHEN rp.Score > 500 THEN 'High Score' ELSE 'Moderate Score' END AS ScoreBand
FROM RankedPosts rp
LEFT JOIN UserActivity ua ON rp.OwnerUserId = ua.UserId
LEFT JOIN TagContributions tc ON rp.PostId = tc.PostId
WHERE rp.ScoreRank <= 100
  AND rp.ViewRank <= 100
  AND tc.DistinctUsersContributingToTags >= 3
  AND ua.PostHistoryCount > 10
  AND rp.AnswerCount > rp.AvgAnswerCountForType
ORDER BY rp.Score DESC
LIMIT 50;