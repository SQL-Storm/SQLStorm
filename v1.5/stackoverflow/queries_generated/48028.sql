-- {"query": "48028.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 508} 
WITH RankedPosts AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        ROW_NUMBER() OVER (ORDER BY p.CreationDate DESC) as rn
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
UserPostAggregates AS (
    SELECT
        up.OwnerUserId,
        COUNT(up.Id) AS TotalPosts,
        AVG(up.Score) AS AvgScore,
        SUM(up.ViewCount) AS TotalViews,
        AVG(up.AnswerCount) AS AvgAnswerCount,
        AVG(up.CommentCount) AS AvgCommentCount,
        AVG(up.FavoriteCount) AS AvgFavoriteCount
    FROM RankedPosts up
    WHERE up.rn <= 10000
    GROUP BY up.OwnerUserId
),
TopUsers AS (
    SELECT
        up.OwnerUserId
    FROM UserPostAggregates up
    ORDER BY up.AvgScore DESC
    LIMIT 500
)
SELECT
    rp.Id AS PostId,
    pt.Name AS PostType,
    u.DisplayName AS OwnerDisplayName,
    rp.CreationDate,
    rp.Score,
    rp.ViewCount,
    rp.AnswerCount,
    rp.CommentCount,
    rp.FavoriteCount,
    upa.TotalPosts AS OwnerTotalPosts,
    upa.AvgScore AS OwnerAvgScore,
    upa.TotalViews AS OwnerTotalViews,
    upa.AvgAnswerCount AS OwnerAvgAnswerCount,
    upa.AvgCommentCount AS OwnerAvgCommentCount,
    upa.AvgFavoriteCount AS OwnerAvgFavoriteCount
FROM RankedPosts rp
JOIN PostTypes pt ON rp.PostTypeId = pt.Id
JOIN Users u ON rp.OwnerUserId = u.Id
JOIN UserPostAggregates upa ON rp.OwnerUserId = upa.OwnerUserId
WHERE rp.rn <= 5000 AND rp.OwnerUserId IN (SELECT OwnerUserId FROM TopUsers)
ORDER BY rp.CreationDate DESC
LIMIT 1000;