-- {"query": "48081.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 910} 
WITH QuestionStats AS (
    SELECT
        p.Id AS QuestionId,
        p.Title,
        p.CreationDate AS QuestionCreationDate,
        u.DisplayName AS OwnerDisplayName,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ViewCount,
        p.Score AS QuestionScore,
        (SELECT COUNT(*) FROM Votes WHERE PostId = p.Id AND VoteTypeId = 2) AS UpVotes,
        (SELECT COUNT(*) FROM Votes WHERE PostId = p.Id AND VoteTypeId = 3) AS DownVotes,
        (SELECT COUNT(*) FROM Votes WHERE PostId = p.Id AND VoteTypeId = 5) AS FavoriteVotes,
        (SELECT COUNT(*) FROM Comments WHERE PostId = p.Id) AS TotalComments,
        (SELECT COUNT(*) FROM PostHistory WHERE PostId = p.Id AND PostHistoryTypeId IN (4, 6)) AS EditHistoryCount,
        p.ClosedDate,
        CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS IsClosed,
        ROW_NUMBER() OVER (ORDER BY p.CreationDate DESC) AS RowNum
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1
),
AnswerStats AS (
    SELECT
        a.ParentId AS QuestionId,
        COUNT(a.Id) AS AnswerCount,
        SUM(a.Score) AS TotalAnswerScore,
        AVG(a.Score) AS AverageAnswerScore,
        COUNT(CASE WHEN p.AcceptedAnswerId = a.Id THEN 1 ELSE NULL END) AS IsAcceptedAnswerPresent
    FROM Posts a
    JOIN Posts p ON a.ParentId = p.Id
    WHERE a.PostTypeId = 2
    GROUP BY a.ParentId
),
UserEngagement AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN p.Id ELSE NULL END) AS QuestionsAsked,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN p.Id ELSE NULL END) AS AnswersGiven,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) AS TotalQuestionScore,
        SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) AS TotalAnswerScore,
        COUNT(b.Id) AS BadgesEarned
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation
)
SELECT
    qs.Title AS QuestionTitle,
    qs.QuestionCreationDate,
    qs.OwnerDisplayName,
    qs.AnswerCount AS DirectAnswerCount,
    COALESCE(ans.AnswerCount, 0) AS TotalAnswers,
    COALESCE(ans.TotalAnswerScore, 0) AS TotalAnswerScore,
    COALESCE(ans.AverageAnswerScore, 0) AS AverageAnswerScore,
    qs.FavoriteCount AS FavoriteCount,
    qs.ViewCount,
    qs.QuestionScore,
    qs.UpVotes AS QuestionUpVotes,
    qs.DownVotes AS QuestionDownVotes,
    qs.FavoriteVotes AS QuestionFavoriteVotes,
    qs.TotalComments AS QuestionComments,
    qs.EditHistoryCount AS QuestionEditHistory,
    qs.IsClosed,
    qs.ClosedDate,
    ue.QuestionsAsked AS OwnerQuestionsAsked,
    ue.AnswersGiven AS OwnerAnswersGiven,
    ue.Reputation AS OwnerReputation,
    ue.BadgesEarned AS OwnerBadgesEarned
FROM QuestionStats qs
LEFT JOIN AnswerStats ans ON qs.QuestionId = ans.QuestionId
LEFT JOIN UserEngagement ue ON qs.OwnerDisplayName = ue.DisplayName
WHERE qs.RowNum BETWEEN 1 AND 1000
ORDER BY qs.QuestionCreationDate DESC;