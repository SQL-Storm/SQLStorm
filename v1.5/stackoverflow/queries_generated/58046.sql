-- {"query": "58046.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2033, "output_tokens": 1381} 

WITH ActiveUsers AS (
    SELECT u.Id, u.DisplayName, u.Reputation, u.CreationDate,
           (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1) AS QuestionCount,
           (SELECT AVG(p.Score) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1) AS AvgQuestionScore
    FROM Users u
    WHERE u.Reputation > 1000
      AND EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = u.Id AND p.CreationDate >= NOW() - INTERVAL '1 YEAR')
), UserVotes AS (
    SELECT v.UserId, 
           COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpvotesGiven,
           COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownvotesGiven,
           COUNT(CASE WHEN v.VoteTypeId = 8 THEN 1 END) AS BountiesStarted
    FROM Votes v
    GROUP BY v.UserId
), PostStats AS (
    SELECT p.OwnerUserId,
           COUNT(DISTINCT c.Id) AS TotalComments,
           COUNT(DISTINCT ph.Id) FILTER (WHERE ph.PostHistoryTypeId IN (2,5,8)) AS EditsReceived,
           STRING_AGG(DISTINCT pt.Name, ', ') AS PostTypesInvolved
    FROM Posts p
    LEFT JOIN Comments c ON c.PostId = p.Id
    LEFT JOIN PostHistory ph ON ph.PostId = p.Id
    LEFT JOIN PostTypes pt ON pt.Id = p.PostTypeId
    GROUP BY p.OwnerUserId
), BadgeSummary AS (
    SELECT b.UserId,
           COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
           COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
           COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges,
           RANK() OVER (ORDER BY COUNT(*) DESC) AS BadgeRank
    FROM Badges b
    GROUP BY b.UserId
)
SELECT au.DisplayName, au.Reputation, au.QuestionCount, au.AvgQuestionScore,
       uv.UpvotesGiven, uv.DownvotesGiven, uv.BountiesStarted,
       ps.TotalComments, ps.EditsReceived, ps.PostTypesInvolved,
       bs.GoldBadges, bs.SilverBadges, bs.BronzeBadges, bs.BadgeRank,
       (SELECT COUNT(*) FROM Posts p 
        WHERE p.OwnerUserId = au.Id 
        AND p.Id IN (SELECT AcceptedAnswerId FROM Posts WHERE OwnerUserId = au.Id)) AS AcceptedAnswers,
       (SELECT ARRAY_AGG(DISTINCT tag) FROM (
           SELECT UNNEST(STRING_TO_ARRAY(SUBSTRING(Tags FROM 2 FOR LENGTH(Tags)-2), '><')) AS tag
           FROM Posts WHERE OwnerUserId = au.Id
        ) t) AS UniqueTagsUsed
FROM ActiveUsers au
JOIN UserVotes uv ON uv.UserId = au.Id
JOIN PostStats ps ON ps.OwnerUserId = au.Id
JOIN BadgeSummary bs ON bs.UserId = au.Id
WHERE au.QuestionCount > 10
  AND bs.GoldBadges + bs.SilverBadges + bs.BronzeBadges > 5
ORDER BY au.Reputation DESC, bs.BadgeRank, uv.UpvotesGiven DESC
LIMIT 100;
