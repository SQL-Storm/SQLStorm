-- {"query": "3052.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4.1-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 899} 
WITH UserReputation AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY u.LastAccessDate DESC) AS Rank
    FROM Users u
),
LatestUserReputation AS (
    SELECT 
        UserId,
        DisplayName,
        Reputation
    FROM UserReputation
    WHERE Rank = 1
),
PostAnswerCounts AS (
    SELECT 
        p.PostTypeId,
        p.Id,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.CommentCount,
        COUNT(a.Id) AS AnswerCount
    FROM Posts p
    LEFT JOIN Posts a ON a.ParentId = p.Id AND a.PostTypeId = 2
    WHERE p.PostTypeId = 1
    GROUP BY p.PostTypeId, p.Id, p.OwnerUserId, p.CreationDate, p.Score, p.CommentCount
),
QuestionAnswerStats AS (
    SELECT
        p.Id AS QuestionId,
        p.Title,
        p.Tags,
        p.CreationDate,
        p.Score AS QuestionScore,
        p.AnswerCount,
        coalesce(u.DisplayName, 'Community User') AS OwnerDisplayName,
        coalesce(u.Reputation, 0) AS OwnerReputation,
        COUNT(DISTINCT c.Id) AS TotalComments,
        MAX(p.LastActivityDate) AS LastActivity
    FROM Posts p
    LEFT JOIN Posts a ON a.ParentId = p.Id AND a.PostTypeId = 2
    LEFT JOIN Comments c ON c.PostId = p.Id
    LEFT JOIN LatestUserReputation u ON u.UserId = p.OwnerUserId
    WHERE p.PostTypeId = 1
    GROUP BY p.Id, p.Title, p.Tags, p.CreationDate, p.Score, p.AnswerCount, u.DisplayName, u.Reputation
),
QuestionAnswerStatsWithAnswers AS (
    SELECT 
        qa.*,
        a.Id AS AcceptedAnswerId,
        a.Score AS AcceptedAnswerScore,
        a.CreationDate AS AnswerCreationDate,
        a.CommentCount AS AcceptedAnswerComments
    FROM QuestionAnswerStats qa
    LEFT JOIN Posts a ON qa.OwnerUserId = a.OwnerUserId AND a.PostTypeId = 2 AND a.Id = (SELECT AcceptedAnswerId FROM Posts WHERE Id = qa.QuestionId)
),
WeightedScore AS (
    SELECT 
        q.*, 
        (q.QuestionScore + q.AnswerCount * 2 + q.TotalComments * 0.5) AS CalculatedScore
    FROM QuestionAnswerStatsWithAnswers q
),
FinalResults AS (
    SELECT 
        ws.QuestionId,
        ws.Title,
        ws.Tags,
        ws.CreationDate,
        ws.OwnerDisplayName,
        ws.OwnerReputation,
        ws.AnswerCount,
        ws.TotalComments,
        ws.LastActivity,
        ws.AcceptedAnswerId,
        ws.AcceptedAnswerScore,
        ws.AnswerCreationDate AS AcceptedAnswerCreationDate,
        ws.AcceptedAnswerComments,
        ws.CalculatedScore
    FROM WeightedScore ws
)
SELECT 
    fr.QuestionId,
    fr.Title,
    string_agg(tag, ', ' ORDER BY tag) AS TagList,
    fr.CreationDate,
    fr.OwnerDisplayName,
    fr.OwnerReputation,
    fr.AnswerCount,
    fr.TotalComments,
    fr.LastActivity,
    fr.AcceptedAnswerId,
    fr.AcceptedAnswerScore,
    fr.AcceptedAnswerCreationDate,
    fr.AcceptedAnswerComments,
    ROUND(fr.CalculatedScore, 2) AS ScoreBenchmark
FROM FinalResults fr
LEFT JOIN LATERAL (
    SELECT 
        unnest(string_to_array(substring(fr.Tags, 2, length(fr.Tags) - 2), '><')) AS tag
) AS tags_alias ON true
GROUP BY 
    fr.QuestionId,
    fr.Title,
    fr.CreationDate,
    fr.OwnerDisplayName,
    fr.OwnerReputation,
    fr.AnswerCount,
    fr.TotalComments,
    fr.LastActivity,
    fr.AcceptedAnswerId,
    fr.AcceptedAnswerScore,
    fr.AcceptedAnswerCreationDate,
    fr.AcceptedAnswerComments,
    fr.CalculatedScore
ORDER BY fr.CalculatedScore DESC
LIMIT 100;