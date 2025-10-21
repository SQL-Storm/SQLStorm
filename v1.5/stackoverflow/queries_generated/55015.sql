-- {"query": "55015.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2048, "output_tokens": 1895} 
WITH TagQuestions AS (
    SELECT p.Id AS QuestionId,
           p.OwnerUserId,
           regexp_split_to_table(p.Tags, '><') AS Tag
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.Tags IS NOT NULL
),
Answers AS (
    SELECT a.Id AS AnswerId,
           a.OwnerUserId,
           a.ParentId,
           a.Score,
           tq.Tag
    FROM Posts a
    JOIN TagQuestions tq ON a.ParentId = tq.QuestionId
    WHERE a.PostTypeId = 2
),
AnswerVotes AS (
    SELECT ans.AnswerId,
           ans.OwnerUserId,
           ans.Tag,
           ans.Score,
           COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpVoteCount
    FROM Answers ans
    LEFT JOIN Votes v ON v.PostId = ans.AnswerId AND v.VoteTypeId = 2
    GROUP BY ans.AnswerId, ans.OwnerUserId, ans.Tag, ans.Score
),
UserTagStats AS (
    SELECT av.Tag,
           av.OwnerUserId AS UserId,
           COUNT(*) AS AnswerCount,
           AVG(av.Score)::numeric(10,2) AS AvgScore,
           SUM(av.UpVoteCount) AS TotalUpVotes
    FROM AnswerVotes av
    GROUP BY av.Tag, av.OwnerUserId
    HAVING COUNT(*) >= 5
),
UserInfo AS (
    SELECT u.Id,
           u.DisplayName,
           u.Reputation,
           u.CreationDate,
           u.Views,
           u.UpVotes,
           u.DownVotes
    FROM Users u
),
UserBadgeAgg AS (
    SELECT b.UserId,
           COUNT(*) AS BadgeCount,
           SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS Gold,
           SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS Silver,
           SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS Bronze
    FROM Badges b
    GROUP BY b.UserId
),
RankedUsers AS (
    SELECT uts.Tag,
           ui.DisplayName,
           ui.Reputation,
           uts.AnswerCount,
           uts.AvgScore,
           ub.Gold,
           ub.Silver,
           ub.Bronze,
           ROW_NUMBER() OVER (PARTITION BY uts.Tag ORDER BY uts.AvgScore DESC, uts.AnswerCount DESC) AS rn
    FROM UserTagStats uts
    JOIN UserInfo ui ON ui.Id = uts.UserId
    LEFT JOIN UserBadgeAgg ub ON ub.UserId = uts.UserId
)
SELECT Tag,
       DisplayName,
       Reputation,
       AnswerCount,
       AvgScore,
       Gold,
       Silver,
       Bronze
FROM RankedUsers
WHERE rn <= 5
ORDER BY Tag, rn;