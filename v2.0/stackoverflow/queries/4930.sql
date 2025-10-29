-- {"query": "4930.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1530}
WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.PostTypeId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        pt.Name AS PostTypeName,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) as rn_desc,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate ASC) as rn_asc,
        AVG(CAST(p.Score AS DOUBLE PRECISION)) OVER (PARTITION BY p.PostTypeId) as avg_score_per_type
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    WHERE p.OwnerUserId IS NOT NULL AND p.OwnerUserId <> -1
),
UserPostActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(rp.PostId) AS TotalPosts,
        SUM(CASE WHEN rp.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN rp.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        SUM(rp.PostScore) AS TotalScoreReceived,
        SUM(CASE WHEN rp.ClosedDate IS NOT NULL THEN 1 ELSE 0 END) AS ClosedPostsCount,
        AVG(CAST(rp.PostScore AS DOUBLE PRECISION)) AS AvgScorePerPost,
        MAX(rp.PostCreationDate) AS LatestPostDate
    FROM Users u
    LEFT JOIN RankedPosts rp ON u.Id = rp.OwnerUserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
RecentHighScoringQuestions AS (
    SELECT
        rp.PostId,
        rp.OwnerUserId,
        rp.PostTypeName,
        rp.PostCreationDate,
        rp.PostScore,
        rp.AnswerCount,
        rp.CommentCount,
        rp.FavoriteCount,
        rp.avg_score_per_type,
        u.DisplayName AS OwnerDisplayName,
        CAST(EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - rp.PostCreationDate)) / 86400 AS INTEGER) AS DaysSinceCreation,
        rp.PostTypeId,
        rp.rn_asc
    FROM RankedPosts rp
    JOIN Users u ON rp.OwnerUserId = u.Id
    WHERE rp.PostTypeId = 1
      AND rp.rn_asc <= 100
      AND rp.PostScore > rp.avg_score_per_type * 1.5
      AND rp.PostScore > 10
      AND CAST(EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - rp.PostCreationDate)) / 86400 AS INTEGER) < 365
),
UserCommentsOnHighScoringQuestions AS (
    SELECT
        c.UserId,
        c.PostId,
        c.CreationDate AS CommentCreationDate,
        c.Score AS CommentScore,
        c.Text AS CommentText,
        CASE
            WHEN POSITION('best' IN LOWER(c.Text)) > 0 THEN 'Positive'
            WHEN POSITION('great' IN LOWER(c.Text)) > 0 THEN 'Positive'
            WHEN POSITION('excellent' IN LOWER(c.Text)) > 0 THEN 'Positive'
            WHEN POSITION('useful' IN LOWER(c.Text)) > 0 THEN 'Positive'
            WHEN POSITION('thank' IN LOWER(c.Text)) > 0 THEN 'Positive'
            WHEN POSITION('agree' IN LOWER(c.Text)) > 0 THEN 'Positive'
            WHEN POSITION('disagree' IN LOWER(c.Text)) > 0 THEN 'Negative'
            WHEN POSITION('wrong' IN LOWER(c.Text)) > 0 THEN 'Negative'
            WHEN POSITION('bad' IN LOWER(c.Text)) > 0 THEN 'Negative'
            ELSE 'Neutral'
        END AS Sentiment,
        ROW_NUMBER() OVER (PARTITION BY c.PostId ORDER BY c.CreationDate ASC) as comment_rn_asc
    FROM Comments c
    JOIN RecentHighScoringQuestions rhsq ON c.PostId = rhsq.PostId
    WHERE c.UserId IS NOT NULL AND c.UserId <> -1 AND c.Score >= 0
)
SELECT
    upa.DisplayName AS UserDisplayName,
    upa.Reputation,
    upa.UserCreationDate,
    upa.TotalPosts,
    upa.QuestionCount,
    upa.AnswerCount,
    upa.TotalScoreReceived,
    upa.ClosedPostsCount,
    upa.AvgScorePerPost,
    upa.LatestPostDate,
    rhsq.PostId AS TopQuestionId,
    rhsq.PostTypeName,
    rhsq.PostScore AS TopQuestionScore,
    rhsq.AnswerCount AS TopQuestionAnswerCount,
    rhsq.FavoriteCount AS TopQuestionFavoriteCount,
    rhsq.DaysSinceCreation AS DaysSinceTopQuestionCreation,
    ucc.UserId AS CommenterUserId,
    ucc.CommenterDisplayName,
    ucc.CommentCreationDate,
    ucc.CommentScore AS CommentScoreOnTopQuestion,
    ucc.Sentiment AS CommentSentiment,
    ucc.CommentText AS CommentOnTopQuestion
FROM UserPostActivity upa
JOIN RecentHighScoringQuestions rhsq ON upa.UserId = rhsq.OwnerUserId
LEFT JOIN (
    SELECT
        ucc.UserId,
        u.DisplayName AS CommenterDisplayName,
        ucc.PostId,
        ucc.CommentCreationDate,
        ucc.CommentScore,
        ucc.Sentiment,
        ucc.CommentText
    FROM UserCommentsOnHighScoringQuestions ucc
    JOIN Users u ON ucc.UserId = u.Id
    WHERE ucc.comment_rn_asc = 1
) ucc ON rhsq.PostId = ucc.PostId
WHERE upa.TotalPosts > 50
  AND upa.Reputation > 1000
  AND upa.UserCreationDate < (DATE '2024-10-01' - INTERVAL '1 year')
  AND rhsq.PostScore > 50
  AND ucc.UserId IS NOT NULL
GROUP BY
    upa.DisplayName,
    upa.Reputation,
    upa.UserCreationDate,
    upa.TotalPosts,
    upa.QuestionCount,
    upa.AnswerCount,
    upa.TotalScoreReceived,
    upa.ClosedPostsCount,
    upa.AvgScorePerPost,
    upa.LatestPostDate,
    rhsq.PostId,
    rhsq.PostTypeName,
    rhsq.PostScore,
    rhsq.AnswerCount,
    rhsq.FavoriteCount,
    rhsq.DaysSinceCreation,
    ucc.UserId,
    ucc.CommenterDisplayName,
    ucc.CommentCreationDate,
    ucc.CommentScore,
    ucc.Sentiment,
    ucc.CommentText
ORDER BY upa.Reputation DESC, upa.TotalScoreReceived DESC, rhsq.PostScore DESC
LIMIT 100;