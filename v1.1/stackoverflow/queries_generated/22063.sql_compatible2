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
           END AS UserTier,
           us.QuestionCount,
           cs.CommentCount,
           vs.NetVotes,
           us.AvgScore
    FROM UserStats us
    FULL OUTER JOIN CommentStats cs ON us.UserId = cs.UserId
    FULL OUTER JOIN VoteStats vs ON us.UserId = vs.UserId
)
SELECT ru.UserId,
       ru.DisplayName,
       ru.Reputation,
       ru.EngagementScore,
       ru.Rank,
       ru.UserTier,
       ru.QuestionCount,
       ru.CommentCount,
       ru.NetVotes,
       ru.AvgScore,
       (
           SELECT COUNT(*)
           FROM Posts p2
           WHERE p2.OwnerUserId = ru.UserId
             AND p2.Tags IS NOT NULL
             AND EXISTS (
                 SELECT 1
                 FROM (
                   SELECT regexp_split_to_table(
                     CASE
                       WHEN LEFT(p2.Tags,1) = '<' AND RIGHT(p2.Tags,1) = '>' THEN SUBSTRING(p2.Tags FROM 2 FOR (LENGTH(p2.Tags) - 2))
                       ELSE p2.Tags
                     END,
                     '><'
                   ) AS tag
                 ) t
                 WHERE t.tag = 'sql'
             )
       ) AS SqlTaggedQuestions,
       CASE WHEN ru.Rank <= 10 THEN 'Top 10' ELSE 'Others' END AS RankGroup
FROM RankedUsers ru
WHERE ru.EngagementScore > 0 OR ru.Reputation > 0

UNION ALL

SELECT NULL AS UserId,
       'Total Stats' AS DisplayName,
       SUM(ru.Reputation) AS Reputation,
       SUM(ru.EngagementScore) AS EngagementScore,
       MAX(ru.Rank) AS Rank,
       STRING_AGG(ru.UserTier, ', ') AS UserTier,
       NULL AS QuestionCount,
       NULL AS CommentCount,
       NULL AS NetVotes,
       NULL AS AvgScore,
       NULL AS SqlTaggedQuestions,
       NULL AS RankGroup
FROM RankedUsers ru
ORDER BY Rank NULLS LAST;