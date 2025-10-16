-- {"query": "5016.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1152} 
WITH RecentActiveUsers AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.CreationDate,
        u.LastAccessDate,
        u.Reputation,
        DENSE_RANK() OVER (ORDER BY u.LastAccessDate DESC) AS ActivityRank
    FROM Users u
    WHERE u.LastAccessDate > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '30 days'
),
HighImpactPosts AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        COALESCE(array_length(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><'), 1), 0) AS TagCount,
        p.AnswerCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.ViewCount DESC) AS UserPostRank
    FROM Posts p
    WHERE p.Score > 5 AND p.ViewCount > 100
),
TopTags AS (
    SELECT
        t.TagName,
        t.Count,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS TagRank
    FROM Tags t
    WHERE t.Count > 1000
),
BadgedUsers AS (
    SELECT DISTINCT
        b.UserId,
        MAX(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS HasGold,
        COUNT(*) as BadgeCount
    FROM Badges b
    WHERE b.Date > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year'
    GROUP BY b.UserId
),
CommentAnalytics AS (
    SELECT
        c.PostId,
        COUNT(*) AS CommentCount,
        MAX(c.Score) AS MaxCommentScore,
        SUM(CASE WHEN c.Score>0 THEN 1 ELSE 0 END) AS PositiveComments
    FROM Comments c
    WHERE c.CreationDate > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '90 days'
    GROUP BY c.PostId
),
AcceptedAnswersCTE AS (
    SELECT
        p.OwnerUserId,
        COUNT(DISTINCT a.Id) AS AcceptedAnswers
    FROM Posts p
    JOIN Posts a ON a.Id = p.AcceptedAnswerId
    WHERE p.PostTypeId = 1
    GROUP BY p.OwnerUserId
),
RecentVotes AS (
    SELECT
        v.PostId,
        COUNT(*) FILTER (WHERE v.VoteTypeId = 2) AS Upvotes,
        COUNT(*) FILTER (WHERE v.VoteTypeId = 3) AS Downvotes,
        COUNT(*) FILTER (WHERE v.VoteTypeId = 5) AS Favorites
    FROM Votes v
    WHERE v.CreationDate > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '60 days'
    GROUP BY v.PostId
)
SELECT
    rau.UserId,
    rau.DisplayName,
    rau.Reputation,
    rau.ActivityRank,
    bu.BadgeCount,
    bu.HasGold,
    COALESCE(aac.AcceptedAnswers,0) AS AcceptedAnswers,
    COALESCE(SUM(hip.Score),0) AS TotalHighScore,
    COALESCE(SUM(hip.ViewCount),0) AS TotalViews,
    AVG(hip.TagCount) AS AvgTagsPerPost,
    tt.TagName AS TopAssociatedTag,
    tt.TagRank,
    COUNT(DISTINCT cma.PostId) AS CommentedHighImpactPosts,
    COALESCE(SUM(rvt.Upvotes),0) AS RecentUpvotes,
    COALESCE(SUM(rvt.Downvotes),0) AS RecentDownvotes,
    COALESCE(SUM(rvt.Favorites),0) AS RecentFavorites
FROM RecentActiveUsers rau
LEFT JOIN BadgedUsers bu ON bu.UserId = rau.UserId
LEFT JOIN AcceptedAnswersCTE aac ON aac.OwnerUserId = rau.UserId
LEFT JOIN HighImpactPosts hip ON hip.OwnerUserId = rau.UserId AND hip.UserPostRank <= 5
LEFT JOIN (
    SELECT
        p.OwnerUserId,
        tt.TagName,
        tt.TagRank
    FROM Posts p
    JOIN TopTags tt ON POSITION(tt.TagName IN p.Tags) > 0
    WHERE p.PostTypeId = 1
    GROUP BY p.OwnerUserId, tt.TagName, tt.TagRank
    HAVING COUNT(*) = (
        SELECT MAX(tag_count)
        FROM (
            SELECT COUNT(*) AS tag_count
            FROM Posts p2
            JOIN TopTags tt2 ON POSITION(tt2.TagName IN p2.Tags) > 0
            WHERE p2.OwnerUserId = p.OwnerUserId
            GROUP BY tt2.TagName
        ) t
    )
    LIMIT 1
) tt ON tt.OwnerUserId = rau.UserId
LEFT JOIN (
    SELECT hip.PostId, ca.PostId AS CommentedPostId
    FROM HighImpactPosts hip
    JOIN CommentAnalytics ca ON ca.PostId = hip.PostId AND ca.MaxCommentScore > 5
) cma ON hip.PostId = cma.PostId
LEFT JOIN RecentVotes rvt ON hip.PostId = rvt.PostId
GROUP BY
    rau.UserId, rau.DisplayName, rau.Reputation, rau.ActivityRank,
    bu.BadgeCount, bu.HasGold, aac.AcceptedAnswers, tt.TagName, tt.TagRank
HAVING COALESCE(SUM(hip.Score),0) > 50
ORDER BY 
    rau.Reputation DESC,
    TotalHighScore DESC,
    TotalViews DESC
FETCH FIRST 50 ROWS ONLY;