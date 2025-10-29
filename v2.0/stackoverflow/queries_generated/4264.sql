-- {"query": "4264.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 815} 

WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        pt.Name AS PostTypeName,
        u.DisplayName AS OwnerDisplayName,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.CreationDate ASC) AS rn
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.Score > 0 AND p.Title IS NOT NULL AND LENGTH(p.Title) > 10
),
PostCommentSummary AS (
    SELECT
        c.PostId,
        COUNT(c.Id) AS CommentCount,
        AVG(c.Score) AS AvgCommentScore,
        MAX(c.CreationDate) AS LatestCommentDate
    FROM Comments c
    GROUP BY c.PostId
),
UserPostActivity AS (
    SELECT
        p.OwnerUserId,
        COUNT(p.Id) AS TotalPostsOwned,
        SUM(p.ViewCount) AS TotalViewsOnPosts,
        AVG(p.AnswerCount) AS AvgAnswersPerQuestion
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
UserVoteSummary AS (
    SELECT
        v.UserId,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE NULL END) AS UpVoteCount,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE NULL END) AS DownVoteCount,
        COUNT(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE NULL END) AS FavoriteCount
    FROM Votes v
    WHERE v.UserId IS NOT NULL
    GROUP BY v.UserId
)
SELECT
    rp.PostId,
    rp.Title,
    rp.PostCreationDate,
    rp.PostScore,
    rp.PostTypeName,
    rp.OwnerDisplayName,
    COALESCE(pcs.CommentCount, 0) AS CommentCount,
    COALESCE(pcs.AvgCommentScore, 0.0) AS AvgCommentScore,
    COALESCE(pcs.LatestCommentDate, rp.PostCreationDate) AS LastActivityAfterCreation,
    COALESCE(upa.TotalPostsOwned, 0) AS OwnerTotalPosts,
    COALESCE(upa.TotalViewsOnPosts, 0) AS OwnerTotalViews,
    COALESCE(uvs.UpVoteCount, 0) AS OwnerUpVoteCount,
    COALESCE(uvs.DownVoteCount, 0) AS OwnerDownVoteCount,
    CASE
        WHEN rp.PostScore > 1000 THEN 'Highly Scored'
        WHEN rp.PostScore > 100 THEN 'Moderately Scored'
        ELSE 'Low Scored'
    END AS ScoreCategory,
    CASE
        WHEN pcs.LatestCommentDate > rp.PostCreationDate + INTERVAL '7 day' THEN 'Active Discussion'
        ELSE 'Limited Discussion'
    END AS DiscussionLevel
FROM RankedPosts rp
LEFT JOIN PostCommentSummary pcs ON rp.PostId = pcs.PostId
LEFT JOIN UserPostActivity upa ON rp.OwnerUserId = upa.OwnerUserId
LEFT JOIN UserVoteSummary uvs ON rp.OwnerUserId = uvs.UserId
WHERE rp.rn <= 50 AND rp.PostTypeName IN ('Question', 'Answer')
ORDER BY rp.PostScore DESC, rp.PostCreationDate ASC
LIMIT 100;
