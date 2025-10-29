-- {"query": "4087.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1004}
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
        ROW_NUMBER() OVER(PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC) AS rn_score_view,
        AVG(CAST(p.Score AS DOUBLE PRECISION)) OVER(PARTITION BY p.PostTypeId) AS avg_score_by_type,
        LAG(p.CreationDate, 1, p.CreationDate) OVER(PARTITION BY p.PostTypeId ORDER BY p.CreationDate) AS previous_post_creation_date
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId IN (1, 2)
),
PostEngagement AS (
    SELECT
        p.Id AS PostId,
        COUNT(c.Id) AS CommentCountPerPost,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId IN (2, 3)
    GROUP BY p.Id
)
SELECT
    rp.PostId,
    rp.PostTypeName,
    rp.OwnerDisplayName,
    rp.PostCreationDate,
    rp.Score,
    rp.ViewCount,
    rp.AnswerCount,
    rp.CommentCount AS PostCommentCount,
    rp.FavoriteCount,
    pe.CommentCountPerPost,
    pe.UpVoteCount,
    pe.DownVoteCount,
    (rp.Score - rp.avg_score_by_type) AS score_deviation_from_type_avg,
    CASE
        WHEN rp.ClosedDate IS NOT NULL AND rp.ClosedDate > (CAST('2024-10-01' AS DATE) - INTERVAL '30 days') THEN 'Recently Closed'
        WHEN rp.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
        WHEN rp.rn_score_view <= 10 THEN 'Top 10 by Score/Views'
        ELSE 'Regular'
    END AS post_status_category,
    CASE WHEN rp.PostCreationDate < (CAST('2024-10-01' AS DATE) - INTERVAL '1 year') THEN 'Old' ELSE 'New' END AS age_category,
    rp.rn_score_view,
    CASE
        WHEN rp.previous_post_creation_date IS NOT NULL AND rp.PostCreationDate > rp.previous_post_creation_date THEN
            EXTRACT(EPOCH FROM (rp.PostCreationDate - rp.previous_post_creation_date))
        ELSE 0
    END AS time_since_previous_post_of_same_type,
    CASE
        WHEN rp.OwnerDisplayName IS NULL THEN 'Unknown'
        WHEN POSITION(' ' IN rp.OwnerDisplayName) > 0 THEN SUBSTRING(rp.OwnerDisplayName FROM 1 FOR POSITION(' ' IN rp.OwnerDisplayName) - 1)
        ELSE rp.OwnerDisplayName
    END AS owner_first_name_or_placeholder,
    COALESCE(rp.FavoriteCount, 0) + COALESCE(rp.AnswerCount, 0) AS engagement_metric,
    (CAST(rp.ViewCount AS DOUBLE PRECISION) / NULLIF(rp.Score, 0)) AS view_score_ratio
FROM RankedPosts rp
JOIN PostEngagement pe ON rp.PostId = pe.PostId
WHERE (
    rp.Score > 0
    AND rp.ViewCount > 100
    AND rp.PostTypeName = 'Question'
)
OR (rp.PostTypeName = 'Answer' AND rp.Score > 5)
ORDER BY rp.PostCreationDate DESC
LIMIT 100;