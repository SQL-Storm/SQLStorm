-- {"query": "5048.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 864} 
WITH rich_activity AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    u.DisplayName AS OwnerDisplayName,
    COALESCE(a.CountAnswers, 0) AS AnswerCount,
    COALESCE(vs.UpVotes, 0) AS UpVotes,
    COALESCE(vs.DownVotes, 0) AS DownVotes,
    COALESCE(b.CountBadges, 0) AS BadgeCount,
    COALESCE(lt.Name, 'Unknown') AS LinkTypeName,
    CASE
      WHEN p.OwnerUserId IS NULL THEN 'Unknown'
      WHEN u.Reputation >= 1000 THEN 'High'
      WHEN u.Reputation >= 100 THEN 'Medium'
      ELSE 'Low'
    END AS OwnerReputationBucket,
    ARRAY_AGG(DISTINCT t.TagName) FILTER (WHERE t.TagName IS NOT NULL) AS TagList
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN (
      SELECT PostId, COUNT(*) AS CountAnswers
      FROM Posts
      WHERE PostTypeId = 2
      GROUP BY PostId
  ) a ON p.Id = a.PostId
  LEFT JOIN (
      SELECT PostId, SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
             SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
      FROM Votes
      GROUP BY PostId
  ) vs ON p.Id = vs.PostId
  LEFT JOIN (
      SELECT PostId, COUNT(*) AS CountBadges
      FROM Badges
      GROUP BY PostId
  ) b ON p.Id = b.PostId
  LEFT JOIN (
      SELECT Id, Name
      FROM LinkTypes
  ) lt ON p.Id = p.Id AND 1=1 -- placeholder to allow outer join pattern
  LEFT JOIN lateral (
      SELECT unnest(string_to_array(
        substr(p.Tags, 2, length(p.Tags) - 2),
        '><'
      )) AS TagName
    ) t ON TRUE
  GROUP BY
    p.Id, p.PostTypeId, p.Title, p.Tags, p.CreationDate, p.LastActivityDate,
    p.Score, p.ViewCount, p.OwnerUserId, u.DisplayName, a.CountAnswers,
    vs.UpVotes, vs.DownVotes, b.CountBadges, lt.Name, u.Reputation
),
recent_activity AS (
  SELECT
    ra.PostId,
    ra.PostTypeId,
    ra.Title,
    ra.TagList,
    ra.CreationDate,
    ra.LastActivityDate,
    ra.Score,
    ra.ViewCount,
    ra.OwnerUserId,
    ra.OwnerDisplayName,
    ra.AnswerCount,
    ra.UpVotes,
    ra.DownVotes,
    ra.BadgeCount,
    ra.TagList,
    ROW_NUMBER() OVER (
      PARTITION BY ra.PostTypeId
      ORDER BY ra.LastActivityDate DESC, ra.Score DESC
    ) AS rn
  FROM rich_activity ra
)
SELECT
  ra.PostId,
  pt.Name AS PostType,
  ra.Title,
  ra.TagList,
  ra.CreationDate,
  ra.LastActivityDate,
  ra.Score,
  ra.ViewCount,
  ra.OwnerDisplayName,
  ra.UpVotes,
  ra.DownVotes,
  ra.AnswerCount,
  ra.BadgeCount,
  ra.TagList AS TagArray,
  ra.OwnerReputationBucket
FROM recent_activity ra
JOIN PostTypes pt ON ra.PostTypeId = pt.Id
WHERE ra.rn = 1
  AND ra.PostTypeId IN (1, 2, 5)
  AND ra.ViewCount > 0
  AND ra.Score >= COALESCE((SELECT AVG(Score) FROM Posts), 0)
ORDER BY ra.LastActivityDate DESC, ra.Score DESC
LIMIT 100;