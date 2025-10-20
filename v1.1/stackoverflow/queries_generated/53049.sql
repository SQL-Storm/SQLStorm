-- {"query": "53049.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2646, "output_tokens": 756} 

WITH TopTags AS (
    SELECT Id, TagName, Count
    FROM Tags
    ORDER BY Count DESC
    LIMIT 10
),
QuestionTags AS (
    SELECT p.Id AS QuestionId, p.CreationDate AS QuestionDate, unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName
    FROM Posts p
    WHERE p.PostTypeId = 1
),
TaggedQuestions AS (
    SELECT qt.QuestionId, qt.QuestionDate, tt.Id AS TagId, tt.TagName
    FROM QuestionTags qt
    JOIN TopTags tt ON qt.TagName = tt.TagName
),
AcceptedAnswers AS (
    SELECT tq.QuestionId, tq.QuestionDate, tq.TagId, tq.TagName, p.Id AS AnswerId, p.OwnerUserId, p.CreationDate AS AnswerDate, p.Score
    FROM TaggedQuestions tq
    JOIN Posts q ON tq.QuestionId = q.Id
    JOIN Posts p ON q.AcceptedAnswerId = p.Id
    WHERE p.PostTypeId = 2
),
UserAnswerStats AS (
    SELECT 
        aa.OwnerUserId, 
        aa.TagId, 
        COUNT(aa.AnswerId) AS AcceptedAnswersCount,
        AVG(aa.Score) AS AvgAnswerScore,
        AVG(EXTRACT(EPOCH FROM (aa.AnswerDate - aa.QuestionDate)) / 3600) AS AvgHoursToAccept,
        SUM(v.UpVotes) AS TotalUpVotesOnAnswers,
        COUNT(DISTINCT ph.Id) AS EditCountOnAnswers,
        COUNT(DISTINCT c.Id) AS CommentCountOnAnswers,
        COUNT(DISTINCT b.Id) AS BadgesEarned
    FROM AcceptedAnswers aa
    JOIN Users u ON aa.OwnerUserId = u.Id
    LEFT JOIN (
        SELECT PostId, COUNT(*) AS UpVotes
        FROM Votes
        WHERE VoteTypeId = 2
        GROUP BY PostId
    ) v ON aa.AnswerId = v.PostId
    LEFT JOIN PostHistory ph ON aa.AnswerId = ph.PostId AND ph.PostHistoryTypeId IN (4,5,6,7,8,9)
    LEFT JOIN Comments c ON aa.AnswerId = c.PostId
    LEFT JOIN Badges b ON aa.OwnerUserId = b.UserId AND b.TagBased = TRUE
    GROUP BY aa.OwnerUserId, aa.TagId
),
RankedUsers AS (
    SELECT 
        us.OwnerUserId, 
        us.TagId, 
        us.AcceptedAnswersCount, 
        us.AvgAnswerScore, 
        us.AvgHoursToAccept, 
        us.TotalUpVotesOnAnswers, 
        us.EditCountOnAnswers, 
        us.CommentCountOnAnswers, 
        us.BadgesEarned,
        ROW_NUMBER() OVER (PARTITION BY us.TagId ORDER BY us.AcceptedAnswersCount DESC, us.AvgAnswerScore DESC, us.TotalUpVotesOnAnswers DESC) AS Rank
    FROM UserAnswerStats us
)
SELECT 
    tt.TagName, 
    u.DisplayName, 
    u.Reputation, 
    ru.AcceptedAnswersCount, 
    ru.AvgAnswerScore, 
    ru.AvgHoursToAccept, 
    ru.TotalUpVotesOnAnswers, 
    ru.EditCountOnAnswers, 
    ru.CommentCountOnAnswers, 
    ru.BadgesEarned
FROM RankedUsers ru
JOIN TopTags tt ON ru.TagId = tt.Id
JOIN Users u ON ru.OwnerUserId = u.Id
WHERE ru.Rank = 1
ORDER BY tt.Count DESC;
