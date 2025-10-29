-- {"query": "4831.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1647} 

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
        u.Reputation AS OwnerReputation,
        ROW_NUMBER() OVER(PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId IN (1, 2)
),
PostEngagement AS (
    SELECT
        p.Id AS PostId,
        COUNT(c.Id) AS CommentCountForPost,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCountForPost,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCountForPost,
        MAX(p.CreationDate) AS LastActivityTimestamp
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId IN (2, 3)
    GROUP BY p.Id
),
UserPostContribution AS (
    SELECT
        u.Id AS UserId,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN p.Id ELSE NULL END) AS QuestionCount,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN p.Id ELSE NULL END) AS AnswerCount,
        SUM(COALESCE(p.Score, 0)) AS TotalScoreOnPosts,
        MAX(p.LastActivityDate) AS LastPostActivityDate,
        AVG(p.Score) AS AverageScorePerPost
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY u.Id
)
SELECT
    rp1.PostId AS PrimaryQuestionId,
    rp1.Title AS PrimaryQuestionTitle,
    rp1.OwnerReputation AS PrimaryQuestionOwnerReputation,
    rp1.Score AS PrimaryQuestionScore,
    rp1.ViewCount AS PrimaryQuestionViewCount,
    rp1.AnswerCount AS PrimaryQuestionAnswerCount,
    rp1.CommentCountForPost AS PrimaryQuestionCommentCount,
    rp1.UpVoteCountForPost AS PrimaryQuestionUpVotes,
    rp1.DownVoteCountForPost AS PrimaryQuestionDownVotes,
    COALESCE(rp2.PostId, -1) AS BestAnswerId,
    COALESCE(rp2.Score, 0) AS BestAnswerScore,
    COALESCE(rp2.OwnerReputation, 0) AS BestAnswerOwnerReputation,
    COALESCE(rp2.CommentCountForPost, 0) AS BestAnswerCommentCount,
    COALESCE(upc.QuestionCount, 0) AS UserTotalQuestions,
    COALESCE(upc.AnswerCount, 0) AS UserTotalAnswers,
    COALESCE(upc.TotalScoreOnPosts, 0) AS UserTotalScoreOnPosts,
    COALESCE(upc.AverageScorePerPost, 0.0) AS UserAverageScorePerPost,
    CASE
        WHEN rp1.FavoriteCount > 100 AND rp1.Score > 50 THEN 'Highly Frequented'
        WHEN rp1.FavoriteCount > 50 AND rp1.Score > 20 THEN 'Moderately Frequented'
        ELSE 'Standard'
    END AS QuestionPopularityCategory,
    rp1.CreationDate AS QuestionCreationDate,
    rp1.LastActivityTimestamp AS QuestionLastActivityDate,
    CASE
        WHEN rp1.OwnerUserId IS NULL THEN 'Anonymous'
        ELSE COALESCE(u.DisplayName, 'Unnamed User')
    END AS QuestionOwnerDisplayName,
    rp1.rn AS RankWithinPostType
FROM RankedPosts rp1
LEFT JOIN RankedPosts rp2 ON rp1.AcceptedAnswerId = rp2.PostId AND rp2.PostTypeId = 2
LEFT JOIN PostEngagement pe ON rp1.PostId = pe.PostId
LEFT JOIN UserPostContribution upc ON rp1.OwnerUserId = upc.UserId
LEFT JOIN Users u ON rp1.OwnerUserId = u.Id
WHERE rp1.PostTypeId = 1
  AND rp1.Score > 0
  AND rp1.CommentCount > 5
  AND rp1.ViewCount > 1000
  AND LOWER(rp1.Title) LIKE '%performance%'
  OR rp1.Tags LIKE '%sql%'
UNION
SELECT
    rp1.PostId AS PrimaryQuestionId,
    rp1.Title AS PrimaryQuestionTitle,
    rp1.OwnerReputation AS PrimaryQuestionOwnerReputation,
    rp1.Score AS PrimaryQuestionScore,
    rp1.ViewCount AS PrimaryQuestionViewCount,
    rp1.AnswerCount AS PrimaryQuestionAnswerCount,
    rp1.CommentCountForPost AS PrimaryQuestionCommentCount,
    rp1.UpVoteCountForPost AS PrimaryQuestionUpVotes,
    rp1.DownVoteCountForPost AS PrimaryQuestionDownVotes,
    COALESCE(rp2.PostId, -1) AS BestAnswerId,
    COALESCE(rp2.Score, 0) AS BestAnswerScore,
    COALESCE(rp2.OwnerReputation, 0) AS BestAnswerOwnerReputation,
    COALESCE(rp2.CommentCountForPost, 0) AS BestAnswerCommentCount,
    COALESCE(upc.QuestionCount, 0) AS UserTotalQuestions,
    COALESCE(upc.AnswerCount, 0) AS UserTotalAnswers,
    COALESCE(upc.TotalScoreOnPosts, 0) AS UserTotalScoreOnPosts,
    COALESCE(upc.AverageScorePerPost, 0.0) AS UserAverageScorePerPost,
    CASE
        WHEN rp1.FavoriteCount > 100 AND rp1.Score > 50 THEN 'Highly Frequented'
        WHEN rp1.FavoriteCount > 50 AND rp1.Score > 20 THEN 'Moderately Frequented'
        ELSE 'Standard'
    END AS QuestionPopularityCategory,
    rp1.CreationDate AS QuestionCreationDate,
    rp1.LastActivityTimestamp AS QuestionLastActivityDate,
    CASE
        WHEN rp1.OwnerUserId IS NULL THEN 'Anonymous'
        ELSE COALESCE(u.DisplayName, 'Unnamed User')
    END AS QuestionOwnerDisplayName,
    rp1.rn AS RankWithinPostType
FROM RankedPosts rp1
LEFT JOIN RankedPosts rp2 ON rp1.AcceptedAnswerId = rp2.PostId AND rp2.PostTypeId = 2
LEFT JOIN PostEngagement pe ON rp1.PostId = pe.PostId
LEFT JOIN UserPostContribution upc ON rp1.OwnerUserId = upc.UserId
LEFT JOIN Users u ON rp1.OwnerUserId = u.Id
WHERE rp1.PostTypeId = 2
  AND rp1.Score > 10
  AND rp1.CommentCountForPost > 2
  AND rp1.UpVoteCountForPost > 5;
