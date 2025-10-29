-- {"query": "4239.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1341} 

WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount AS PostViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        p.ClosedDate,
        pt.Name AS PostTypeName,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    WHERE p.OwnerUserId IS NOT NULL
),
UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(DISTINCT ph.PostId) AS PostHistoryCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotes,
        AVG(COALESCE(c.Score, 0)) AS AvgCommentScore
    FROM Users u
    LEFT JOIN PostHistory ph ON u.Id = ph.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
RecentQuestions AS (
    SELECT
        rp.PostId,
        rp.Title,
        rp.OwnerUserId,
        rp.PostCreationDate,
        rp.PostScore,
        rp.PostViewCount,
        rp.AnswerCount,
        rp.FavoriteCount,
        rp.ClosedDate,
        rp.PostTypeName,
        ua.DisplayName AS OwnerDisplayName,
        ua.Reputation AS OwnerReputation,
        ua.UserCreationDate AS OwnerCreationDate,
        ua.PostHistoryCount AS OwnerPostHistoryCount,
        ua.TotalUpVotes AS OwnerTotalUpVotes,
        ua.TotalDownVotes AS OwnerTotalDownVotes,
        ua.AvgCommentScore AS OwnerAvgCommentScore
    FROM RankedPosts rp
    JOIN UserActivity ua ON rp.OwnerUserId = ua.UserId
    WHERE rp.rn <= 1000 AND rp.PostTypeName = 'Question'
),
HighScoringAnswers AS (
    SELECT
        rp.PostId,
        rp.OwnerUserId,
        rp.PostCreationDate,
        rp.PostScore,
        rp.PostTypeName,
        ua.DisplayName AS AnswererDisplayName,
        ua.Reputation AS AnswererReputation
    FROM RankedPosts rp
    JOIN UserActivity ua ON rp.OwnerUserId = ua.UserId
    WHERE rp.rn <= 5000 AND rp.PostTypeName = 'Answer' AND rp.PostScore > 10
)
SELECT
    rq.Title AS QuestionTitle,
    rq.PostCreationDate AS QuestionCreationDate,
    rq.PostScore AS QuestionScore,
    rq.PostViewCount AS QuestionViewCount,
    rq.AnswerCount AS QuestionAnswerCount,
    rq.FavoriteCount AS QuestionFavoriteCount,
    rq.ClosedDate AS QuestionClosedDate,
    rq.PostTypeName AS QuestionPostType,
    rq.OwnerDisplayName AS QuestionOwnerDisplayName,
    rq.OwnerReputation AS QuestionOwnerReputation,
    rq.OwnerCreationDate AS QuestionOwnerCreationDate,
    rq.OwnerPostHistoryCount AS QuestionOwnerPostHistoryCount,
    rq.OwnerTotalUpVotes AS QuestionOwnerTotalUpVotes,
    rq.OwnerTotalDownVotes AS QuestionOwnerTotalDownVotes,
    rq.OwnerAvgCommentScore AS QuestionOwnerAvgCommentScore,
    COUNT(hsa.PostId) AS NumberOfHighScoringAnswers,
    SUM(hsa.PostScore) AS TotalHighScoringAnswerScore,
    AVG(hsa.AnswererReputation) AS AvgHighScoringAnswererReputation,
    CASE
        WHEN rq.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN rq.PostScore > 100 AND rq.ViewCount > 10000 THEN 'Popular and Highly Scored'
        WHEN rq.AnswerCount > 10 AND rq.PostScore > 50 THEN 'Active and Well-Received'
        ELSE 'Standard'
    END AS QuestionStatusCategory,
    -- Example of a complex string expression with NULL handling
    CONCAT(
        UPPER(SUBSTRING(rq.OwnerDisplayName, 1, 3)),
        '-',
        CAST(rq.PostId AS VARCHAR(10)),
        '-',
        COALESCE(rq.PostTypeName, 'UNKNOWN')
    ) AS GeneratedIdentifier
FROM RecentQuestions rq
LEFT JOIN HighScoringAnswers hsa ON rq.PostId = (
    SELECT ParentId
    FROM Posts
    WHERE Id = hsa.PostId
)
WHERE rq.OwnerReputation > 1000 OR rq.PostScore > 50
GROUP BY
    rq.PostId,
    rq.Title,
    rq.PostCreationDate,
    rq.PostScore,
    rq.PostViewCount,
    rq.AnswerCount,
    rq.FavoriteCount,
    rq.ClosedDate,
    rq.PostTypeName,
    rq.OwnerDisplayName,
    rq.OwnerReputation,
    rq.OwnerCreationDate,
    rq.OwnerPostHistoryCount,
    rq.OwnerTotalUpVotes,
    rq.OwnerTotalDownVotes,
    rq.OwnerAvgCommentScore
HAVING COUNT(hsa.PostId) > 0 OR rq.PostScore > 100 -- Ensure we either have high-scoring answers or a very high-scoring question
ORDER BY rq.PostScore DESC, rq.PostCreationDate DESC
LIMIT 100;
