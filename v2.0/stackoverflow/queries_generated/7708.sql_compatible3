WITH RankedPosts AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        p.Title,
        p.Tags,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS prev_score,
        LEAD(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS next_score,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) AS avg_score,
        CASE 
            WHEN p.Score > (SELECT AVG(Score) FROM Posts WHERE OwnerUserId = p.OwnerUserId) THEN 'Above Average'
            WHEN p.Score < (SELECT AVG(Score) FROM Posts WHERE OwnerUserId = p.OwnerUserId) THEN 'Below Average'
            ELSE 'Average'
        END AS score_category,
        COALESCE(p.Title, 'No Title') AS title_or_default
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) AS total_posts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS question_count,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS answer_count,
        MAX(p.CreationDate) AS last_post_date,
        EXTRACT(EPOCH FROM (u.LastAccessDate - u.CreationDate)) / 86400.0 AS days_since_last_access
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes, u.CreationDate, u.LastAccessDate
    HAVING COUNT(DISTINCT p.Id) > 0
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count AS tag_count,
        t.ExcerptPostId,
        t.WikiPostId,
        COALESCE((SELECT COUNT(*) FROM Posts WHERE Tags LIKE '%' || t.TagName || '%'), 0) AS related_posts,
        (SELECT AVG(p.Score) FROM Posts p WHERE p.Tags LIKE '%' || t.TagName || '%') AS avg_score_for_tag
    FROM Tags t
    WHERE t.Count > 100
),
RecentPosts AS (
    SELECT 
        p.Id,
        p.Title,
        p.Body,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        u.DisplayName AS owner_name,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END AS post_type,
        COALESCE(SUBSTRING(p.Tags FROM 2 FOR (CHAR_LENGTH(p.Tags) - 2)), 'No Tags') AS clean_tags,
        TRIM(BOTH '<' FROM TRIM(BOTH '>' FROM p.Tags)) AS tag_list,
        CASE 
            WHEN p.AnswerCount > 0 THEN 
                (SELECT COUNT(*) FROM Posts WHERE ParentId = p.Id AND PostTypeId = 2)
            ELSE 0 
        END AS answer_count,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS comment_count,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS upvotes,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) AS downvotes
    FROM Posts p
    INNER JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '6 months')
      AND p.PostTypeId IN (1, 2)
      AND p.Score >= 0
),
ActivitySummary AS (
    SELECT 
        rp.Id,
        rp.Title,
        rp.Body,
        rp.Score,
        rp.ViewCount,
        rp.CreationDate,
        rp.owner_name,
        rp.post_type,
        rp.clean_tags,
        rp.answer_count,
        rp.comment_count,
        rp.upvotes,
        rp.downvotes,
        CASE 
            WHEN rp.upvotes > rp.downvotes THEN 'Upvoted'
            WHEN rp.downvotes > rp.upvotes THEN 'Downvoted'
            ELSE 'Neutral'
        END AS vote_status,
        CASE 
            WHEN rp.ViewCount > (SELECT AVG(ViewCount) FROM RecentPosts) THEN 'Popular'
            WHEN rp.ViewCount < (SELECT AVG(ViewCount) FROM RecentPosts) THEN 'Less Popular'
            ELSE 'Average'
        END AS popularity
    FROM RecentPosts rp
),
CombinedAnalysis AS (
    SELECT 
        rs.Id,
        rs.Title,
        rs.Body,
        rs.Score,
        rs.ViewCount,
        rs.CreationDate,
        rs.owner_name,
        rs.post_type,
        rs.clean_tags,
        rs.answer_count,
        rs.comment_count,
        rs.upvotes,
        rs.downvotes,
        rs.vote_status,
        rs.popularity,
        CASE 
            WHEN rs.vote_status = 'Upvoted' THEN 1
            WHEN rs.vote_status = 'Downvoted' THEN -1
            ELSE 0
        END AS vote_impact,
        CASE 
            WHEN rs.Score > 0 AND rs.popularity = 'Popular' THEN 1
            WHEN rs.Score < 0 AND rs.popularity = 'Less Popular' THEN -1
            ELSE 0
        END AS score_popularity_match,
        ROW_NUMBER() OVER (ORDER BY rs.Score DESC, rs.ViewCount DESC) AS rank_by_score_and_views
    FROM ActivitySummary rs
)
SELECT 
    ca.Id,
    ca.Title,
    ca.Score,
    ca.ViewCount,
    ca.CreationDate,
    ca.owner_name,
    ca.post_type,
    ca.clean_tags,
    ca.answer_count,
    ca.comment_count,
    ca.vote_status,
    ca.popularity,
    ca.vote_impact,
    ca.score_popularity_match,
    ca.rank_by_score_and_views,
    CASE 
        WHEN ca.vote_impact = 1 AND ca.score_popularity_match = 1 THEN 'High Impact'
        WHEN ca.vote_impact = -1 AND ca.score_popularity_match = -1 THEN 'Downvoted Popularity'
        ELSE 'Mixed Impact'
    END AS impact_category,
    COUNT(*) OVER () AS total_results,
    AVG(ca.Score) OVER () AS overall_avg_score,
    MAX(ca.ViewCount) OVER () AS max_views,
    MIN(ca.ViewCount) OVER () AS min_views,
    (SELECT COUNT(*) FROM Tags WHERE TagName LIKE '%' || SUBSTRING(ca.clean_tags FROM 1 FOR 10) || '%') AS tag_matches,
    ROUND(CAST(ca.Score AS NUMERIC) / NULLIF(CAST(ca.ViewCount AS NUMERIC), 0) * 100, 2) AS score_per_view_ratio,
    CASE 
        WHEN ca.CreationDate BETWEEN (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 week') AND CAST('2024-10-01 12:34:56' AS timestamp) THEN 'This Week'
        WHEN ca.CreationDate BETWEEN (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 month') AND (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 week') THEN 'Last Month'
        ELSE 'Older'
    END AS recency_bucket
FROM CombinedAnalysis ca
WHERE ca.Score > (SELECT AVG(Score) FROM CombinedAnalysis)
  AND ca.ViewCount > (SELECT AVG(ViewCount) FROM CombinedAnalysis)
  AND ca.clean_tags IS NOT NULL
  AND CHAR_LENGTH(ca.clean_tags) > 0
GROUP BY 
    ca.Id, ca.Title, ca.Score, ca.ViewCount, ca.CreationDate, ca.owner_name,
    ca.post_type, ca.clean_tags, ca.answer_count, ca.comment_count,
    ca.vote_status, ca.popularity, ca.vote_impact, ca.score_popularity_match,
    ca.rank_by_score_and_views, ca.Body, ca.upvotes, ca.downvotes
HAVING 
    COUNT(*) > 0
    AND (
        (ca.rank_by_score_and_views <= 100)
        OR 
        (CHAR_LENGTH(ca.Title) > 50 AND (ROUND(CAST(ca.Score AS NUMERIC) / NULLIF(CAST(ca.ViewCount AS NUMERIC), 0) * 100, 2)) > 0.5)
        OR
        (ca.vote_impact = 1 AND ca.score_popularity_match = 1)
    )
ORDER BY 
    ca.Score DESC, 
    ca.ViewCount DESC,
    ca.rank_by_score_and_views ASC
LIMIT 1000;