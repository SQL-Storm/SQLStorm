-- {"query": "4978.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1116} 

WITH QuestionDetails AS (
    SELECT
        p.Id AS QuestionId,
        p.Title,
        p.CreationDate AS QuestionCreationDate,
        u.DisplayName AS OwnerDisplayName,
        COUNT(a.Id) AS AnswerCount,
        MAX(a.Score) AS MaxAnswerScore,
        SUM(a.CommentCount) AS TotalAnswerComments,
        AVG(a.ViewCount) OVER (PARTITION BY p.PostTypeId) AS AvgQuestionViewCount,
        LAG(p.Score, 1, 0) OVER (ORDER BY p.CreationDate) AS PreviousQuestionScore,
        ROW_NUMBER() OVER (ORDER BY p.Score DESC) AS ScoreRank
    FROM Posts AS p
    JOIN Users AS u ON p.OwnerUserId = u.Id
    LEFT JOIN Posts AS a ON p.Id = a.ParentId AND a.PostTypeId = 2
    WHERE p.PostTypeId = 1 AND p.Score > 0
    GROUP BY p.Id, p.Title, p.CreationDate, u.DisplayName, p.PostTypeId, p.Score
),
UserActivity AS (
    SELECT
        ph.UserId,
        COUNT(DISTINCT ph.PostId) AS PostsModifiedCount,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (2, 5) THEN ph.PostId END) AS BodyEdits,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (1, 4) THEN 1 ELSE 0 END) AS TitleEdits,
        MAX(ph.CreationDate) AS LastPostEditDate
    FROM PostHistory AS ph
    WHERE ph.UserId IS NOT NULL AND ph.PostHistoryTypeId BETWEEN 1 AND 9
    GROUP BY ph.UserId
),
HighValueQuestions AS (
    SELECT
        qd.QuestionId,
        qd.Title,
        qd.OwnerDisplayName,
        qd.AnswerCount,
        qd.MaxAnswerScore,
        qd.TotalAnswerComments,
        qd.AvgQuestionViewCount,
        qd.PreviousQuestionScore,
        qd.ScoreRank,
        CASE WHEN qd.MaxAnswerScore > 100 THEN 'Highly Scored Answers' WHEN qd.TotalAnswerComments > 50 THEN 'High Comment Volume' ELSE 'Standard' END AS QualityIndicator
    FROM QuestionDetails AS qd
    WHERE qd.ScoreRank <= 500
)
SELECT
    hvq.Title AS QuestionTitle,
    hvq.OwnerDisplayName,
    hvq.AnswerCount,
    hvq.MaxAnswerScore,
    hvq.TotalAnswerComments,
    hvq.AvgQuestionViewCount,
    hvq.PreviousQuestionScore,
    hvq.QualityIndicator,
    ua.PostsModifiedCount,
    ua.BodyEdits,
    ua.TitleEdits,
    ua.LastPostEditDate,
    CASE
        WHEN DATEDIFF(day, hvq.QuestionCreationDate, GETDATE()) < 7 THEN 'Recent'
        WHEN DATEDIFF(day, hvq.QuestionCreationDate, GETDATE()) BETWEEN 7 AND 30 THEN 'Monthly'
        ELSE 'Older'
    END AS AgeGroup,
    COALESCE(u.Reputation, 0) AS OwnerReputation,
    CASE WHEN u.DownVotes > u.UpVotes THEN 'NegativeVoteBalance' ELSE 'PositiveVoteBalance' END AS VoteBalanceStatus
FROM HighValueQuestions AS hvq
LEFT JOIN UserActivity AS ua ON hvq.OwnerDisplayName = (SELECT DisplayName FROM Users WHERE Id = (SELECT OwnerUserId FROM Posts WHERE Id = hvq.QuestionId)) -- Correlated Subquery for OwnerDisplayName lookup
LEFT JOIN Users AS u ON hvq.OwnerDisplayName = u.DisplayName AND u.AccountId IS NOT NULL -- Join on DisplayName with NULL check
WHERE hvq.AnswerCount > 0
UNION ALL
SELECT
    'NULL' AS QuestionTitle,
    'NULL' AS OwnerDisplayName,
    0 AS AnswerCount,
    0 AS MaxAnswerScore,
    0 AS TotalAnswerComments,
    AVG(p.ViewCount) AS AvgQuestionViewCount,
    0 AS PreviousQuestionScore,
    'Not Applicable' AS QualityIndicator,
    COUNT(DISTINCT ph.UserId) AS PostsModifiedCount,
    COUNT(CASE WHEN ph.PostHistoryTypeId IN (2, 5) THEN ph.PostId END) AS BodyEdits,
    COUNT(CASE WHEN ph.PostHistoryTypeId IN (1, 4) THEN ph.PostId END) AS TitleEdits,
    MAX(ph.CreationDate) AS LastPostEditDate,
    'Unknown' AS AgeGroup,
    AVG(u.Reputation) AS OwnerReputation,
    'Unknown' AS VoteBalanceStatus
FROM Posts AS p
LEFT JOIN PostHistory AS ph ON p.Id = ph.PostId
LEFT JOIN Users AS u ON ph.UserId = u.Id
WHERE p.PostTypeId = 1 AND p.ClosedDate IS NOT NULL;
