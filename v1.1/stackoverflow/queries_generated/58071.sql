-- {"query": "58071.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2033, "output_tokens": 1094} 

WITH ActiveUsers AS (
    SELECT u.Id, u.DisplayName, u.Reputation, u.CreationDate,
           (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1) AS QuestionCount,
           (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2) AS AnswerCount,
           (SELECT COUNT(*) FROM Comments c WHERE c.UserId = u.Id) AS CommentCount,
           (SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 2) AS UpvotesGiven,
           (SELECT COUNT(*) FROM Votes v WHERE v.PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = u.Id) AND v.VoteTypeId = 2) AS UpvotesReceived
    FROM Users u
    WHERE u.Reputation > 10000 AND u.CreationDate >= '2020-01-01'
),
BadgeSummary AS (
    SELECT UserId,
           SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
           SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
           SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges
    GROUP BY UserId
),
PostHistoryAnalysis AS (
    SELECT ph.UserId,
           COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (2,5,8) THEN ph.PostId END) AS ContentEdits,
           COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.PostId END) AS CloseVotes
    FROM PostHistory ph
    WHERE ph.CreationDate BETWEEN '2023-01-01' AND '2023-12-31'
    GROUP BY ph.UserId
)
SELECT au.*, bs.GoldBadges, bs.SilverBadges, bs.BronzeBadges, pha.ContentEdits, pha.CloseVotes,
       RANK() OVER (ORDER BY (au.QuestionCount * 3 + au.AnswerCount * 2 + au.CommentCount) DESC) AS ActivityRank,
       RANK() OVER (ORDER BY au.UpvotesReceived DESC) AS InfluenceRank
FROM ActiveUsers au
JOIN BadgeSummary bs ON au.Id = bs.UserId
LEFT JOIN PostHistoryAnalysis pha ON au.Id = pha.UserId
WHERE au.AnswerCount > 100 OR au.QuestionCount > 50
ORDER BY au.Reputation DESC, InfluenceRank, ActivityRank
LIMIT 100;
