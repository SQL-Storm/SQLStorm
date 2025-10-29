-- {"query": "4245.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1422} 

WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        pt.Name AS PostTypeName,
        p.OwnerUserId,
        u.DisplayName AS OwnerDisplayName,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC) AS rn_by_score_views,
        AVG(CAST(p.Score AS FLOAT)) OVER (PARTITION BY p.PostTypeId) AS avg_score_by_type,
        COUNT(c.Id) OVER (PARTITION BY p.Id) AS comment_count_for_post,
        CASE
            WHEN p.Tags LIKE '%<sql>%' THEN 'SQL Related'
            WHEN p.Tags LIKE '%<performance>%' THEN 'Performance Related'
            WHEN p.Tags LIKE '%<optimization>%' THEN 'Optimization Related'
            ELSE 'Other'
        END AS tag_category
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON p.Id = c.PostId
    WHERE p.PostTypeId IN (1, 2) -- Questions and Answers
    AND p.CreationDate >= DATE('now', '-365 day')
),
PostVoteAnalysis AS (
    SELECT
        p.Id AS PostId,
        COUNT(CASE WHEN vt.Name = 'UpMod' THEN 1 END) AS upvotes,
        COUNT(CASE WHEN vt.Name = 'DownMod' THEN 1 END) AS downvotes,
        COUNT(CASE WHEN vt.Name = 'Favorite' THEN 1 END) AS favorites,
        SUM(CASE WHEN vt.Name = 'BountyStart' THEN v.BountyAmount ELSE 0 END) AS total_bounty_amount
    FROM Posts p
    JOIN Votes v ON p.Id = v.PostId
    JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    WHERE p.PostTypeId = 1 -- Only for Questions
    GROUP BY p.Id
)
SELECT
    rp.PostId,
    rp.PostTypeName,
    rp.OwnerDisplayName,
    rp.CreationDate,
    rp.Score,
    rp.ViewCount,
    rp.AnswerCount,
    rp.CommentCount,
    rp.FavoriteCount,
    rp.rn_by_score_views,
    rp.avg_score_by_type,
    rp.comment_count_for_post,
    pva.upvotes,
    pva.downvotes,
    pva.favorites,
    pva.total_bounty_amount,
    CASE
        WHEN rp.Score > rp.avg_score_by_type * 1.5 THEN 'Above Average Score'
        WHEN rp.Score < rp.avg_score_by_type * 0.5 THEN 'Below Average Score'
        ELSE 'Average Score'
    END AS score_performance_category,
    rp.tag_category,
    CASE
        WHEN rp.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN rp.FavoriteCount > 100 THEN 'Highly Favorited'
        WHEN rp.ViewCount > 10000 THEN 'Highly Viewed'
        ELSE 'Standard'
    END AS post_status_category,
    UPPER(SUBSTR(rp.OwnerDisplayName, 1, 3)) AS owner_initials,
    CASE WHEN rp.OwnerUserId IS NULL THEN 'Deleted User' ELSE 'Active User' END AS owner_status,
    COALESCE(rp.FavoriteCount, 0) + COALESCE(rp.AnswerCount, 0) AS engagement_score
FROM RankedPosts rp
LEFT JOIN PostVoteAnalysis pva ON rp.PostId = pva.PostId
WHERE rp.rn_by_score_views <= 100 -- Top 100 posts by score/views within each type
AND (rp.tag_category = 'SQL Related' OR rp.tag_category = 'Performance Related')
UNION ALL
SELECT
    rp.PostId,
    rp.PostTypeName,
    rp.OwnerDisplayName,
    rp.CreationDate,
    rp.Score,
    rp.ViewCount,
    rp.AnswerCount,
    rp.CommentCount,
    rp.FavoriteCount,
    rp.rn_by_score_views,
    rp.avg_score_by_type,
    rp.comment_count_for_post,
    pva.upvotes,
    pva.downvotes,
    pva.favorites,
    pva.total_bounty_amount,
    CASE
        WHEN rp.Score > rp.avg_score_by_type * 1.5 THEN 'Above Average Score'
        WHEN rp.Score < rp.avg_score_by_type * 0.5 THEN 'Below Average Score'
        ELSE 'Average Score'
    END AS score_performance_category,
    rp.tag_category,
    CASE
        WHEN rp.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN rp.FavoriteCount > 100 THEN 'Highly Favorited'
        WHEN rp.ViewCount > 10000 THEN 'Highly Viewed'
        ELSE 'Standard'
    END AS post_status_category,
    UPPER(SUBSTR(rp.OwnerDisplayName, 1, 3)) AS owner_initials,
    CASE WHEN rp.OwnerUserId IS NULL THEN 'Deleted User' ELSE 'Active User' END AS owner_status,
    COALESCE(rp.FavoriteCount, 0) + COALESCE(rp.AnswerCount, 0) AS engagement_score
FROM RankedPosts rp
LEFT JOIN PostVoteAnalysis pva ON rp.PostId = pva.PostId
WHERE rp.rn_by_score_views <= 50 -- Top 50 posts for other categories
AND rp.tag_category = 'Other'
ORDER BY rp.PostTypeName, rp.rn_by_score_views;
