-- {"query": "4508.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1343} 
WITH QuestionScores AS (
    SELECT
        p.Id AS QuestionId,
        p.Title,
        p.OwnerUserId,
        p.CreationDate AS QuestionCreationDate,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpVotes,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownVotes,
        SUM(CASE WHEN v.VoteTypeId = 8 THEN v.BountyAmount ELSE 0 END) AS TotalBountyAmount,
        ROW_NUMBER() OVER (ORDER BY COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) DESC, COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) ASC, SUM(CASE WHEN v.VoteTypeId = 8 THEN v.BountyAmount ELSE 0 END) DESC) AS ScoreRank
    FROM Posts p
    JOIN Votes v ON p.Id = v.PostId
    WHERE p.PostTypeId = 1
    GROUP BY p.Id, p.Title, p.OwnerUserId, p.CreationDate
),
AnswerDetails AS (
    SELECT
        a.Id AS AnswerId,
        a.ParentId AS QuestionId,
        a.OwnerUserId AS AnswerOwnerUserId,
        a.CreationDate AS AnswerCreationDate,
        a.Score AS AnswerScore,
        CASE
            WHEN qs.AcceptedAnswerId = a.Id THEN 1
            ELSE 0
        END AS IsAcceptedAnswer,
        ROW_NUMBER() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC) AS AnswerRankWithinQuestion
    FROM Posts a
    LEFT JOIN Posts qs ON a.ParentId = qs.Id
    WHERE a.PostTypeId = 2
),
UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS QuestionsAsked,
        COUNT(DISTINCT a.AnswerId) AS AnswersGiven,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (2, 5) THEN 1 ELSE 0 END) AS EditsMade,
        MAX(COALESCE(u.LastAccessDate, u.CreationDate)) AS LastSeen
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 1
    LEFT JOIN Posts a ON u.Id = a.OwnerUserId AND a.PostTypeId = 2
    LEFT JOIN PostHistory ph ON u.Id = ph.UserId
    WHERE u.Id > 0
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.LastAccessDate, u.CreationDate
)
SELECT
    qs.Title AS QuestionTitle,
    qs.UpVotes,
    qs.DownVotes,
    qs.TotalBountyAmount,
    ua_q.DisplayName AS QuestionOwnerName,
    ua_q.Reputation AS QuestionOwnerReputation,
    ua_q.LastSeen AS QuestionOwnerLastSeen,
    ad.AnswerRankWithinQuestion,
    ad.AnswerOwnerUserId,
    ua_a.DisplayName AS AnswerOwnerName,
    ua_a.Reputation AS AnswerOwnerReputation,
    ad.AnswerScore,
    CASE
        WHEN ad.IsAcceptedAnswer = 1 THEN 'Yes'
        ELSE 'No'
    END AS IsAccepted,
    CASE
        WHEN qs.QuestionCreationDate < DATE('now', '-365 day') AND ad.AnswerCreationDate < DATE('now', '-365 day') THEN 'Old'
        WHEN qs.QuestionCreationDate >= DATE('now', '-365 day') AND ad.AnswerCreationDate >= DATE('now', '-365 day') THEN 'Recent'
        ELSE 'MixedAge'
    END AS AgeCategory,
    CONCAT(
        ua_a.QuestionsAsked,
        ' Qs, ',
        ua_a.AnswersGiven,
        ' As, ',
        ua_a.EditsMade,
        ' Edits'
    ) AS AnswererStats
FROM QuestionScores qs
LEFT JOIN AnswerDetails ad ON qs.QuestionId = ad.QuestionId
LEFT JOIN Users ua_q ON qs.OwnerUserId = ua_q.Id
LEFT JOIN Users ua_a ON ad.AnswerOwnerUserId = ua_a.Id
LEFT JOIN UserActivity ua_a ON ad.AnswerOwnerUserId = ua_a.UserId
WHERE
    qs.ScoreRank <= 100
    AND ad.AnswerRankWithinQuestion <= 3
    AND (ua_a.Reputation > 1000 OR ad.IsAcceptedAnswer = 1)
    AND ua_q.DisplayName IS NOT NULL
    AND ua_a.DisplayName <> 'Community'
    AND LOWER(qs.Title) LIKE '%performance%'
UNION
SELECT
    qs.Title AS QuestionTitle,
    qs.UpVotes,
    qs.DownVotes,
    qs.TotalBountyAmount,
    ua_q.DisplayName AS QuestionOwnerName,
    ua_q.Reputation AS QuestionOwnerReputation,
    ua_q.LastSeen AS QuestionOwnerLastSeen,
    NULL AS AnswerRankWithinQuestion,
    NULL AS AnswerOwnerUserId,
    NULL AS AnswerOwnerName,
    NULL AS AnswerOwnerReputation,
    NULL AS AnswerScore,
    'N/A' AS IsAccepted,
    CASE
        WHEN qs.QuestionCreationDate < DATE('now', '-365 day') THEN 'Old'
        ELSE 'Recent'
    END AS AgeCategory,
    'No Answers Provided' AS AnswererStats
FROM QuestionScores qs
LEFT JOIN Users ua_q ON qs.OwnerUserId = ua_q.Id
WHERE qs.ScoreRank <= 100
AND NOT EXISTS (SELECT 1 FROM AnswerDetails ad WHERE ad.QuestionId = qs.QuestionId AND ad.AnswerOwnerUserId <> qs.OwnerUserId)
AND LOWER(qs.Title) LIKE '%performance%';