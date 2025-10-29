-- {"query": "4243.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1205}
WITH
  QuestionEdits AS (
    SELECT
      ph.PostId,
      COUNT(ph.Id) AS NumberOfEdits,
      MAX(ph.CreationDate) AS LastEditDate
    FROM PostHistory ph
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6)
      AND ph.PostId IN (
        SELECT Id FROM Posts WHERE PostTypeId = 1
      )
    GROUP BY
      ph.PostId
  ),
  AnswerMetrics AS (
    SELECT
      p.ParentId AS QuestionId,
      COUNT(p.Id) AS NumberOfAnswers,
      SUM(p.Score) AS TotalAnswerScore,
      AVG(p.Score) AS AverageAnswerScore,
      MAX(p.CreationDate) AS LatestAnswerDate
    FROM Posts p
    WHERE
      p.PostTypeId = 2
    GROUP BY
      p.ParentId
  ),
  TopUsers AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      (
        SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1
      ) AS GoldBadges,
      (
        SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2
      ) AS SilverBadges,
      (
        SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3
      ) AS BronzeBadges
    FROM Users u
    WHERE
      u.Reputation > 10000
  ),
  PostEngagement AS (
    SELECT
      p.Id AS PostId,
      COUNT(DISTINCT c.Id) AS CommentCount,
      COUNT(DISTINCT v.Id) AS VoteCount,
      ROW_NUMBER() OVER (
        ORDER BY
          COUNT(DISTINCT c.Id) DESC,
          COUNT(DISTINCT v.Id) DESC
      ) AS EngagementRank
    FROM Posts p
    LEFT JOIN Comments c
      ON p.Id = c.PostId
    LEFT JOIN Votes v
      ON p.Id = v.PostId AND v.VoteTypeId IN (2, 3)
    GROUP BY
      p.Id
  )
SELECT
  q.Id AS QuestionId,
  q.Title,
  q.CreationDate AS QuestionCreationDate,
  q.Score AS QuestionScore,
  q.OwnerUserId,
  COALESCE(tu.DisplayName, 'Unknown User') AS OwnerDisplayName,
  q.AnswerCount,
  COALESCE(am.NumberOfAnswers, 0) AS ActualAnswerCount,
  COALESCE(am.TotalAnswerScore, 0) AS TotalAnswerScore,
  COALESCE(am.AverageAnswerScore, 0.0) AS AverageAnswerScore,
  COALESCE(qe.NumberOfEdits, 0) AS NumberOfEdits,
  qe.LastEditDate,
  CASE
    WHEN q.ClosedDate IS NOT NULL THEN 'Closed'
    WHEN q.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
    ELSE 'Open'
  END AS PostStatus,
  pe.EngagementRank,
  tu.Reputation AS OwnerReputation,
  tu.GoldBadges,
  tu.SilverBadges,
  tu.BronzeBadges,
  SUBSTRING(q.Tags FROM 2 FOR (POSITION('>' IN q.Tags) - 2)) AS FirstTag,
  CASE
    WHEN q.ViewCount > 1000000 THEN 'Very High Traffic'
    WHEN q.ViewCount > 100000 THEN 'High Traffic'
    ELSE 'Normal Traffic'
  END AS TrafficCategory,
  (
    SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = q.Id AND pl.LinkTypeId = 3
  ) AS DuplicateLinks,
  (
    SELECT SUM(CASE WHEN c.UserId IS NOT NULL THEN 1 ELSE 0 END)
    FROM Comments c
    WHERE
      c.PostId = q.Id
      AND c.CreationDate > (cast('2024-10-01' as date) - INTERVAL '7 day')
  ) AS RecentCommenterCount
FROM Posts q
LEFT JOIN AnswerMetrics am
  ON q.Id = am.QuestionId
LEFT JOIN QuestionEdits qe
  ON q.Id = qe.PostId
LEFT JOIN TopUsers tu
  ON q.OwnerUserId = tu.UserId
LEFT JOIN PostEngagement pe
  ON q.Id = pe.PostId
WHERE
  q.PostTypeId = 1
  AND q.CreationDate >= DATE '2023-01-01'
  AND (
    q.Score > 50 OR COALESCE(am.TotalAnswerScore, 0) > 200 OR COALESCE(qe.NumberOfEdits, 0) > 5
  )
  AND q.Title IS NOT NULL
  AND q.OwnerUserId IS NOT NULL
ORDER BY
  q.LastActivityDate DESC
LIMIT 100;