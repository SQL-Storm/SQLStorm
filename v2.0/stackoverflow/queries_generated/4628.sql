-- {"query": "4628.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1025} 

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
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC) AS RankByScoreAndViews,
        COUNT(c.Id) OVER (PARTITION BY p.Id) AS CommentCountForPost,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) OVER (PARTITION BY p.Id) AS UpVoteCountForPost,
        AVG(CAST(p.Score AS FLOAT)) OVER (PARTITION BY p.PostTypeId) AS AvgScoreForPostType,
        LAG(p.Score, 1, 0) OVER (ORDER BY p.CreationDate) AS PreviousPostScore
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE p.PostTypeId IN (1, 2) AND p.CreationDate >= DATE('now', '-1 year')
),
TopRatedQuestions AS (
    SELECT
        Id,
        Title,
        OwnerUserId,
        Score,
        ViewCount,
        Tags,
        CreationDate
    FROM Posts
    WHERE PostTypeId = 1
      AND Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1)
      AND ViewCount > (SELECT AVG(ViewCount) FROM Posts WHERE PostTypeId = 1)
      AND DATE(CreationDate) BETWEEN DATE('now', '-1 year') AND DATE('now')
),
UserPostActivity AS (
    SELECT
        UserId,
        COUNT(DISTINCT Id) AS TotalPosts,
        SUM(CASE WHEN PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        MAX(CreationDate) AS LastPostDate
    FROM Posts
    WHERE OwnerUserId IS NOT NULL
    GROUP BY UserId
    HAVING COUNT(Id) > 10
)
SELECT
    rp.PostId,
    rp.PostTypeName,
    rp.OwnerDisplayName,
    rp.Score,
    rp.ViewCount,
    rp.RankByScoreAndViews,
    rp.CommentCountForPost,
    rp.UpVoteCountForPost,
    rp.AvgScoreForPostType,
    rp.PreviousPostScore,
    CASE
        WHEN rp.Score > rp.AvgScoreForPostType * 1.5 THEN 'High Performer'
        WHEN rp.Score < rp.AvgScoreForPostType * 0.5 THEN 'Low Performer'
        ELSE 'Average Performer'
    END AS PerformanceCategory,
    trq.Title AS TopQuestionTitle,
    trq.Tags AS TopQuestionTags,
    upa.TotalPosts AS UserTotalPosts,
    upa.QuestionCount AS UserQuestionCount,
    upa.AnswerCount AS UserAnswerCount,
    CASE
        WHEN rp.ClosedDate IS NOT NULL AND rp.CommunityOwnedDate IS NOT NULL THEN 'Closed & Community Owned'
        WHEN rp.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN rp.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
        ELSE 'Active'
    END AS PostStatus,
    COALESCE(rp.OwnerDisplayName, 'Anonymous') AS DisplayOwner,
    CASE WHEN rp.Score < 0 THEN 'Negative Score' WHEN rp.Score >= 1000 THEN 'Highly Scored' ELSE 'Moderate Score' END AS ScoreBracket,
    SUBSTRING(rp.OwnerDisplayName, 1, 3) AS FirstThreeCharsOfOwnerName
FROM RankedPosts rp
LEFT JOIN TopRatedQuestions trq ON rp.PostId = trq.Id
LEFT JOIN UserPostActivity upa ON rp.OwnerUserId = upa.UserId
WHERE rp.PostTypeId = 1 -- Focusing on Questions for this particular benchmark
ORDER BY rp.RankByScoreAndViews
LIMIT 100;
