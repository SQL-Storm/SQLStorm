-- {"query": "55054.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2048, "output_tokens": 1690} 

WITH recent_questions AS (
    SELECT p.Id AS QuestionId,
           p.Tags,
           p.CreationDate
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= CURRENT_DATE - INTERVAL '1 year'
),
question_tags AS (
    SELECT q.QuestionId,
           unnest(string_to_array(substring(q.Tags, 2, length(q.Tags) - 2), '><')) AS TagName
    FROM recent_questions q
),
answers AS (
    SELECT a.Id AS AnswerId,
           a.ParentId AS QuestionId,
           a.OwnerUserId,
           a.Score,
           a.CreationDate
    FROM Posts a
    WHERE a.PostTypeId = 2
      AND a.CreationDate >= CURRENT_DATE - INTERVAL '1 year'
),
answer_votes AS (
    SELECT v.PostId AS AnswerId,
           COUNT(*) FILTER (WHERE v.VoteTypeId = 2) AS UpVotes,
           COUNT(*) FILTER (WHERE v.VoteTypeId = 3) AS DownVotes
    FROM Votes v
    JOIN answers a ON v.PostId = a.AnswerId
    GROUP BY v.PostId
),
user_rep AS (
    SELECT u.Id AS UserId,
           u.Reputation,
           u.DisplayName
    FROM Users u
),
tag_stats AS (
    SELECT t.TagName,
           COUNT(DISTINCT qt.QuestionId)                         AS QuestionCount,
           SUM(a.Score)                                          AS TotalAnswerScore,
           AVG(a.Score)                                          AS AvgAnswerScore,
           COUNT(DISTINCT a.AnswerId)                            AS AnswerCount
    FROM question_tags qt
    JOIN Tags t ON t.TagName = qt.TagName
    LEFT JOIN answers a ON a.QuestionId = qt.QuestionId
    GROUP BY t.TagName
),
top_contributors AS (
    SELECT qt.TagName,
           ur.UserId,
           ur.DisplayName,
           SUM(a.Score)                                 AS UserScore,
           SUM(av.UpVotes)                              AS UserUpVotes,
           ROW_NUMBER() OVER (PARTITION BY qt.TagName ORDER BY SUM(a.Score) DESC) AS rn
    FROM question_tags qt
    JOIN answers a ON a.QuestionId = qt.QuestionId
    JOIN user_rep ur ON ur.UserId = a.OwnerUserId
    LEFT JOIN answer_votes av ON av.AnswerId = a.AnswerId
    GROUP BY qt.TagName, ur.UserId, ur.DisplayName
)
SELECT ts.TagName,
       ts.QuestionCount,
       ts.AnswerCount,
       ts.TotalAnswerScore,
       ts.AvgAnswerScore,
       t.Id                               AS TagId,
       t.Count                            AS TagGlobalCount,
       json_agg(
           json_build_object(
               'UserId',       tc.UserId,
               'DisplayName',  tc.DisplayName,
               'Score',        tc.UserScore,
               'UpVotes',      tc.UserUpVotes
           )
           ORDER BY tc.UserScore DESC
       ) FILTER (WHERE tc.rn <= 5)       AS TopContributors
FROM tag_stats ts
JOIN Tags t ON t.TagName = ts.TagName
LEFT JOIN top_contributors tc ON tc.TagName = ts.TagName
GROUP BY ts.TagName,
         ts.QuestionCount,
         ts.AnswerCount,
         ts.TotalAnswerScore,
         ts.AvgAnswerScore,
         t.Id,
         t.Count
ORDER BY ts.QuestionCount DESC
LIMIT 100;
