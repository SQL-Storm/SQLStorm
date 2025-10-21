-- {"query": "48084.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 623} 

WITH QuestionScores AS (
    SELECT
        p.Id AS QuestionId,
        p.Title,
        p.OwnerUserId,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpVoteCount,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownVoteCount,
        COUNT(a.Id) AS AnswerCount,
        SUM(CASE WHEN a.OwnerUserId IS NOT NULL THEN 1 ELSE 0 END) AS AnswerWithUserIdCount,
        SUM(CASE WHEN c.UserId IS NOT NULL THEN 1 ELSE 0 END) AS CommenterCount,
        ROW_NUMBER() OVER (ORDER BY p.CreationDate DESC) AS RowNum
    FROM Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId IN (2, 3)
    LEFT JOIN Posts a ON p.Id = a.ParentId AND a.PostTypeId = 2
    LEFT JOIN Comments c ON p.Id = c.PostId
    WHERE p.PostTypeId = 1 -- Questions
    GROUP BY p.Id, p.Title, p.OwnerUserId
),
UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(qs.QuestionId) AS QuestionsAsked,
        COUNT(CASE WHEN qs.AnswerCount > 0 THEN qs.QuestionId END) AS QuestionsAnswered,
        COUNT(b.Id) AS BadgesEarned,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.CreationDate ASC) AS UserRank
    FROM Users u
    LEFT JOIN QuestionScores qs ON u.Id = qs.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Id > 0 -- Exclude community user
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
)
SELECT
    qs.QuestionId,
    qs.Title AS QuestionTitle,
    ua.DisplayName AS OwnerDisplayName,
    ua.Reputation AS OwnerReputation,
    qs.UpVoteCount,
    qs.DownVoteCount,
    qs.AnswerCount,
    qs.AnswerWithUserIdCount,
    qs.CommenterCount,
    ua.QuestionsAsked,
    ua.QuestionsAnswered,
    ua.BadgesEarned,
    ua.UserRank,
    qs.RowNum AS QuestionRank
FROM QuestionScores qs
JOIN UserActivity ua ON qs.OwnerUserId = ua.UserId
WHERE qs.RowNum <= 1000 AND ua.UserRank <= 500
ORDER BY qs.RowNum, ua.UserRank;
