-- {"query": "4877.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1195} 

WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount AS PostViewCount,
        p.FavoriteCount AS PostFavoriteCount,
        p.AnswerCount AS PostAnswerCount,
        p.CommentCount AS PostCommentCount,
        pt.Name AS PostTypeName,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS rn_by_type_date,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) OVER (PARTITION BY p.Id) AS UpVoteCount,
        COUNT(c.Id) OVER (PARTITION BY p.Id) AS CommentCountFromCommentsTable,
        AVG(CAST(p.Score AS FLOAT)) OVER (PARTITION BY p.PostTypeId) AS AvgScoreByType
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId = 2
    LEFT JOIN Comments c ON p.Id = c.PostId
    WHERE p.OwnerUserId IS NOT NULL AND p.PostTypeId IN (1, 2)
),
UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(DISTINCT ph.PostId) AS PostEditCount,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (2, 5) THEN 1 ELSE 0 END) AS BodyEditCount,
        MAX(ph.CreationDate) AS LastEditDate
    FROM Users u
    LEFT JOIN PostHistory ph ON u.Id = ph.UserId
    WHERE u.Id > 0
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
TopQuestions AS (
    SELECT
        Id,
        Title,
        OwnerUserId,
        Score,
        FavoriteCount,
        CreationDate
    FROM Posts
    WHERE PostTypeId = 1 AND Score > 1000 AND FavoriteCount > 50
),
QuestionAnswerStats AS (
    SELECT
        q.Id AS QuestionId,
        COUNT(a.Id) AS AnswerCount,
        SUM(CASE WHEN q.AcceptedAnswerId = a.Id THEN 1 ELSE 0 END) AS IsAcceptedAnswer,
        MAX(a.Score) AS MaxAnswerScore,
        AVG(CAST(a.Score AS FLOAT)) AS AvgAnswerScore
    FROM Posts q
    LEFT JOIN Posts a ON q.Id = a.ParentId
    WHERE q.PostTypeId = 1
    GROUP BY q.Id
)
SELECT
    rp.PostId,
    rp.PostTypeName,
    rp.PostCreationDate,
    rp.PostScore,
    rp.PostViewCount,
    rp.PostFavoriteCount,
    rp.PostAnswerCount,
    rp.PostCommentCount,
    rp.UpVoteCount,
    rp.CommentCountFromCommentsTable,
    rp.AvgScoreByType,
    ua.DisplayName AS OwnerDisplayName,
    ua.Reputation AS OwnerReputation,
    ua.UserCreationDate AS OwnerCreationDate,
    ua.PostEditCount,
    ua.BodyEditCount,
    CASE WHEN rp.PostTypeId = 1 THEN tq.Title ELSE NULL END AS QuestionTitle,
    CASE WHEN rp.PostTypeId = 1 THEN qas.AnswerCount ELSE NULL END AS NumberOfAnswers,
    CASE WHEN rp.PostTypeId = 1 THEN qas.IsAcceptedAnswer ELSE NULL END AS AcceptedAnswerIndicator,
    CASE WHEN rp.PostTypeId = 1 THEN qas.MaxAnswerScore ELSE NULL END AS MaxAnswerScore,
    CASE WHEN rp.PostTypeId = 1 THEN qas.AvgAnswerScore ELSE NULL END AS AvgAnswerScore,
    COALESCE(tq.Score, -1) AS TopQuestionScoreOrFallback,
    CASE WHEN rp.PostFavoriteCount > 100 AND rp.PostScore > 50 THEN 'Highly Engaged'
         WHEN rp.PostViewCount > 10000 THEN 'High Traffic'
         ELSE 'Standard'
    END AS PostEngagementCategory,
    UPPER(SUBSTRING(rp.PostTypeName FROM 1 FOR 1)) || LOWER(SUBSTRING(rp.PostTypeName FROM 2)) AS FormattedPostTypeName
FROM RankedPosts rp
LEFT JOIN UserActivity ua ON rp.OwnerUserId = ua.UserId
LEFT JOIN TopQuestions tq ON rp.PostId = tq.Id
LEFT JOIN QuestionAnswerStats qas ON rp.PostId = qas.QuestionId
WHERE rp.rn_by_type_date <= 1000
  AND (rp.PostScore > ua.Reputation * 0.1 OR ua.Reputation IS NULL)
  AND rp.PostTypeName <> 'WikiPlaceholder'
  AND EXISTS (SELECT 1 FROM Comments c WHERE c.PostId = rp.PostId AND LENGTH(c.Text) > 100)
ORDER BY rp.PostCreationDate DESC, rp.PostScore DESC;
