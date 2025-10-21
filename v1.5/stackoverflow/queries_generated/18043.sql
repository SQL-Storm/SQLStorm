-- {"query": "18043.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1395} 

WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.Title,
        p.CreationDate AS PostCreationDate,
        pt.Name AS PostTypeName,
        ROW_NUMBER() OVER(PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    WHERE p.Score > 10 AND p.CreationDate > '2023-01-01'
),
UserContribution AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT ph.Id) AS PostHistoryCount,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (2, 5) THEN 1 ELSE 0 END) AS BodyEdits,
        AVG(CASE WHEN v.VoteTypeId = 2 THEN 1.0 ELSE 0.0 END) AS AvgUpvotesOnPosts
    FROM Users u
    LEFT JOIN PostHistory ph ON u.Id = ph.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId AND v.VoteTypeId = 2
    WHERE u.CreationDate < '2023-01-01'
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING u.Reputation > 1000
),
HighScoringAnswers AS (
    SELECT
        p.Id AS AnswerId,
        p.ParentId AS QuestionId,
        p.Score AS AnswerScore,
        p.OwnerUserId AS AnswerOwnerUserId,
        ROW_NUMBER() OVER(PARTITION BY p.ParentId ORDER BY p.Score DESC, p.CreationDate ASC) AS AnswerRank
    FROM Posts p
    WHERE p.PostTypeId = 2 AND p.Score > 5
),
QuestionDetails AS (
    SELECT
        q.Id AS QuestionId,
        q.Title AS QuestionTitle,
        q.OwnerUserId AS QuestionOwnerUserId,
        q.AcceptedAnswerId,
        COALESCE(ha.AnswerId, -1) AS BestAnswerId,
        COALESCE(ha.AnswerScore, 0) AS BestAnswerScore,
        COALESCE(q.AnswerCount, 0) AS TotalAnswers,
        CASE WHEN q.ClosedDate IS NOT NULL THEN 'Closed' ELSE 'Open' END AS QuestionStatus
    FROM Posts q
    LEFT JOIN HighScoringAnswers ha ON q.Id = ha.QuestionId AND ha.AnswerRank = 1
    WHERE q.PostTypeId = 1 AND q.CreationDate > '2023-06-01'
)
SELECT
    rp.PostId,
    rp.Title AS RankedPostTitle,
    rp.PostTypeName,
    ud.DisplayName AS ContributorDisplayName,
    ud.Reputation AS ContributorReputation,
    ud.PostHistoryCount,
    ud.BodyEdits,
    ud.AvgUpvotesOnPosts,
    qd.QuestionTitle,
    qd.QuestionStatus,
    qd.TotalAnswers,
    qd.BestAnswerScore,
    CASE
        WHEN qd.AcceptedAnswerId IS NOT NULL AND qd.AcceptedAnswerId = qd.BestAnswerId THEN 'Accepted and Highest Scored'
        WHEN qd.AcceptedAnswerId IS NOT NULL THEN 'Accepted Answer Present'
        WHEN qd.BestAnswerId <> -1 THEN 'Highest Scored Answer Present'
        ELSE 'No High-Scoring Answers'
    END AS AnswerQualityMetric,
    UPPER(SUBSTRING(COALESCE(ud.DisplayName, 'Unknown User') FROM 1 FOR 3)) AS UserDisplayNamePrefix,
    (ud.Reputation + ud.PostHistoryCount * 5) AS PerformanceScore,
    IIF(ud.Reputation > 5000, 'High Reputation', 'Standard Reputation') AS ReputationLevel,
    CASE
        WHEN qd.TotalAnswers BETWEEN 1 AND 10 THEN 'Low Activity'
        WHEN qd.TotalAnswers BETWEEN 11 AND 50 THEN 'Medium Activity'
        ELSE 'High Activity'
    END AS AnswerActivityLevel
FROM RankedPosts rp
LEFT JOIN UserContribution ud ON rp.OwnerUserId = ud.UserId
LEFT JOIN QuestionDetails qd ON rp.PostId = qd.QuestionId
WHERE ud.Reputation IS NOT NULL
UNION
SELECT
    rp.PostId,
    rp.Title AS RankedPostTitle,
    rp.PostTypeName,
    ud.DisplayName AS ContributorDisplayName,
    ud.Reputation AS ContributorReputation,
    ud.PostHistoryCount,
    ud.BodyEdits,
    ud.AvgUpvotesOnPosts,
    qd.QuestionTitle,
    qd.QuestionStatus,
    qd.TotalAnswers,
    qd.BestAnswerScore,
    CASE
        WHEN qd.AcceptedAnswerId IS NOT NULL AND qd.AcceptedAnswerId = qd.BestAnswerId THEN 'Accepted and Highest Scored'
        WHEN qd.AcceptedAnswerId IS NOT NULL THEN 'Accepted Answer Present'
        WHEN qd.BestAnswerId <> -1 THEN 'Highest Scored Answer Present'
        ELSE 'No High-Scoring Answers'
    END AS AnswerQualityMetric,
    UPPER(SUBSTRING(COALESCE(ud.DisplayName, 'Unknown User') FROM 1 FOR 3)) AS UserDisplayNamePrefix,
    (ud.Reputation + ud.PostHistoryCount * 5) AS PerformanceScore,
    IIF(ud.Reputation > 5000, 'High Reputation', 'Standard Reputation') AS ReputationLevel,
    CASE
        WHEN qd.TotalAnswers BETWEEN 1 AND 10 THEN 'Low Activity'
        WHEN qd.TotalAnswers BETWEEN 11 AND 50 THEN 'Medium Activity'
        ELSE 'High Activity'
    END AS AnswerActivityLevel
FROM RankedPosts rp
RIGHT JOIN UserContribution ud ON rp.OwnerUserId = ud.UserId
LEFT JOIN QuestionDetails qd ON rp.PostId = qd.QuestionId
WHERE rp.rn <= 50 AND ud.DisplayName LIKE '%dev%';
