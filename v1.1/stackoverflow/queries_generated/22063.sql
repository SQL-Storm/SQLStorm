-- {"query": "22063.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2204, "output_tokens": 698} 
WITH UserStats AS (
    SELECT u.Id AS UserId,
           u.DisplayName,
           u.Reputation,
           COUNT(p.Id) AS QuestionCount,
           COUNT(DISTINCT pl.RelatedPostId) AS DuplicateLinks,
           AVG(p.Score) AS AvgScore,
           SUM(CASE WHEN ph.PostHistoryTypeId IN (10,11) THEN 1 ELSE 0 END) AS HistoryEvents
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 1
    LEFT JOIN PostLinks pl ON p.Id = pl.PostId AND pl.LinkTypeId = 3
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
CommentStats AS (
    SELECT c.UserId,
           COUNT(c.Id) AS CommentCount,
           STRING_AGG(LOWER(SUBSTRING(c.Text, 1, 50)), ' ') AS CommentSnippet
    FROM Comments c
    GROUP BY c.UserId
),
VoteStats AS (
    SELECT v.UserId,
           SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 WHEN v.VoteTypeId = 3 THEN -1 ELSE 0 END) AS NetVotes,
           COUNT(v.Id) AS TotalVotes
    FROM Votes v
    WHERE v.VoteTypeId IN (2,3)
    GROUP BY v.UserId
),
RankedUsers AS (
    SELECT us.UserId,
           us.DisplayName,
           us.Reputation,
           COALESCE(us.QuestionCount, 0) + COALESCE(cs.CommentCount, 0) + COALESCE(vs.NetVotes, 0) AS EngagementScore,
           DENSE_RANK() OVER (ORDER BY (COALESCE(us.QuestionCount, 0) + COALESCE(cs.CommentCount, 0) + COALESCE(vs.NetVotes, 0)) DESC) AS Rank,
           CASE 
               WHEN us.AvgScore > 10 AND us.Reputation > 1000 THEN 'Elite'
               WHEN us.AvgScore BETWEEN 0 AND 5 THEN 'Novice'
               ELSE 'Regular'
           END AS UserTier
    FROM UserStats us
    FULL OUTER JOIN CommentStats cs ON us.UserId = cs.UserId
    FULL OUTER JOIN VoteStats vs ON us.UserId = vs.UserId
)
SELECT ru.*,
       (
           SELECT COUNT(*)
           FROM Posts p2
           WHERE p2.OwnerUserId = ru.UserId
           AND p2.Tags IS NOT NULL
           AND EXISTS (
               SELECT 1
               FROM string_to_array(SUBSTRING(p2.Tags, 2, LENGTH(p2.Tags)-2), '><') AS tag
               WHERE tag = 'sql'
           )
       ) AS SqlTaggedQuestions,
       CASE WHEN ru.Rank <= 10 THEN 'Top 10' ELSE 'Others' END AS RankGroup
FROM RankedUsers ru
WHERE ru.EngagementScore > 0 OR ru.Reputation > 0
UNION
SELECT NULL AS UserId,
       'Total Stats' AS DisplayName,
       SUM(Reputation) AS Reputation,
       SUM(EngagementScore) AS EngagementScore,
       MAX(Rank) AS Rank,
       STRING_AGG(UserTier, ', ') AS UserTier
FROM RankedUsers
ORDER BY Rank NULLS LAST;