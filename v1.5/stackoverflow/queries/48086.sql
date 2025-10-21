-- {"query": "48086.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 626} 
WITH RankedUserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 5 THEN 1 ELSE NULL END) AS EditsToBody,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 4 THEN 1 ELSE NULL END) AS EditsToTitle,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 6 THEN 1 ELSE NULL END) AS EditsToTags,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE NULL END) AS UpVotes,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE NULL END) AS DownVotes,
        COUNT(DISTINCT p.Id) AS QuestionsAnswered,
        ROW_NUMBER() OVER (ORDER BY COUNT(CASE WHEN ph.PostHistoryTypeId = 5 THEN 1 ELSE NULL END) DESC) AS RankByBodyEdits,
        ROW_NUMBER() OVER (ORDER BY COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE NULL END) DESC) AS RankByUpVotes
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN PostHistory ph ON u.Id = ph.UserId AND p.Id = ph.PostId
    LEFT JOIN Votes v ON u.Id = v.UserId AND p.Id = v.PostId
    WHERE u.Id > 0
    GROUP BY u.Id, u.DisplayName
),
TopQuestions AS (
    SELECT
        p.Id,
        p.Title,
        p.Score,
        p.AnswerCount,
        p.ViewCount,
        ROW_NUMBER() OVER (ORDER BY p.Score DESC) AS RankByScore
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.Score > 100 AND p.AnswerCount > 10
)
SELECT
    rua.UserId,
    rua.DisplayName,
    rua.EditsToBody,
    rua.EditsToTitle,
    rua.EditsToTags,
    rua.UpVotes,
    rua.DownVotes,
    rua.QuestionsAnswered,
    rua.RankByBodyEdits,
    rua.RankByUpVotes,
    tq.Title AS TopQuestionTitle,
    tq.Score AS TopQuestionScore,
    tq.RankByScore AS TopQuestionRank
FROM RankedUserActivity rua
JOIN TopQuestions tq ON rua.RankByUpVotes <= 10 AND tq.RankByScore <= 5
WHERE rua.EditsToBody > 50 OR rua.UpVotes > 200
ORDER BY rua.EditsToBody DESC, rua.UpVotes DESC;