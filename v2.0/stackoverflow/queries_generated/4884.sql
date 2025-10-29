-- {"query": "4884.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 827} 
WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        pt.Name AS PostTypeName,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS rn_by_type_date,
        COUNT(c.Id) OVER (PARTITION BY p.Id) AS CommentCountPerPost,
        SUM(COALESCE(v.VoteTypeId, 0)) OVER (PARTITION BY p.Id) AS TotalVoteTypeSum
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE p.OwnerUserId IS NOT NULL
      AND p.CreationDate BETWEEN DATE('now', '-1 year') AND DATE('now')
),
UserPostStats AS (
    SELECT
        rp.OwnerUserId,
        COUNT(rp.PostId) AS TotalPostsOwned,
        AVG(rp.Score) AS AverageScore,
        SUM(CASE WHEN rp.ClosedDate IS NOT NULL THEN 1 ELSE 0 END) AS ClosedPostsCount,
        MAX(rp.TotalVoteTypeSum) AS MaxVoteSumForUser
    FROM RankedPosts rp
    WHERE rp.PostTypeId IN (1, 2) -- Questions and Answers
    GROUP BY rp.OwnerUserId
)
SELECT
    rp.PostId,
    rp.PostTypeName,
    rp.Score,
    rp.ViewCount,
    rp.CommentCountPerPost,
    rp.TotalVoteTypeSum,
    u.DisplayName AS OwnerDisplayName,
    COALESCE(ups.TotalPostsOwned, 0) AS UserTotalPostsOwned,
    COALESCE(ups.AverageScore, 0) AS UserAverageScore,
    ups.ClosedPostsCount AS UserClosedPosts,
    CASE
        WHEN rp.Score > 100 AND rp.CommentCountPerPost > 50 THEN 'Highly Engaged'
        WHEN rp.Score < 0 THEN 'Negatively Scored'
        WHEN rp.FavoriteCount > 10 THEN 'Popular'
        ELSE 'Standard'
    END AS PostEngagementCategory,
    CASE
        WHEN ups.MaxVoteSumForUser > 0 AND rp.TotalVoteTypeSum = ups.MaxVoteSumForUser THEN 'User_Top_Vote_Activity_Post'
        ELSE 'User_Non_Top_Vote_Activity_Post'
    END AS UserVoteActivityRank,
    CASE
        WHEN rp.rn_by_type_date <= 10 THEN 'Top_10_By_Type_And_Date'
        ELSE 'Other_Posts'
    END AS RankByCategory,
    LENGTH(rp.Title) AS TitleLength,
    UPPER(SUBSTRING(rp.Title, 1, 3)) AS TitlePrefixUpper,
    (rp.Score + rp.FavoriteCount) AS CombinedScoreFavorite
FROM RankedPosts rp
LEFT JOIN Users u ON rp.OwnerUserId = u.Id
LEFT JOIN UserPostStats ups ON rp.OwnerUserId = ups.OwnerUserId
WHERE rp.rn_by_type_date <= 50
  AND rp.Score >= 0
  AND (rp.PostTypeId = 1 OR rp.PostTypeId = 2)
ORDER BY rp.Score DESC, rp.ViewCount DESC
LIMIT 100;