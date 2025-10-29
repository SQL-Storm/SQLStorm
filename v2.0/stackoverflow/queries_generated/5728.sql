-- {"query": "5728.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 886} 
WITH top_questions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.LastActivityDate,
    p.PostTypeId,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.ViewCount DESC, p.CreationDate DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= NOW() - INTERVAL '1 year'
),
popular_authors AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    u.LastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.Location,
    u.ProfileImageUrl,
    u.EmailHash,
    COUNT(t.PostId) AS RecentTopQuestions
  FROM top_questions t
  JOIN Users u ON t.OwnerUserId = u.Id
  WHERE t.rn = 1
  GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Views, u.UpVotes, u.DownVotes, u.Location, u.ProfileImageUrl, u.EmailHash
),
activity_enrichment AS (
  SELECT
    q.PostId,
    q.Title,
    q.CreationDate,
    q.Score,
    q.ViewCount,
    q.OwnerUserId,
    q.LastActivityDate,
    q.Tags,
    STRING_AGG(CONCAT('Tag:', trim(t.TagName)), ',') FILTER (WHERE t.TagName IS NOT NULL) AS TagNames,
    (SELECT MAX(v.CreationDate) FROM Votes v WHERE v.PostId = q.PostId AND v.VoteTypeId IN (2,7)) AS LastEngagementDate
  FROM top_questions q
  LEFT JOIN UNNEST(string_to_array(q.Tags, '>')) AS t(TagName)
    ON TRUE
  GROUP BY
    q.PostId, q.Title, q.CreationDate, q.Score, q.ViewCount, q.OwnerUserId, q.LastActivityDate, q.Tags
)
SELECT
  a.UserId,
  a.DisplayName AS AuthorName,
  a.Reputation,
  a.UserCreationDate,
  a.LastAccessDate,
  a.Views,
  a.UpVotes,
  a.DownVotes,
  a.Location,
  a.ProfileImageUrl,
  a.EmailHash,
  a.RecentTopQuestions,
  (SELECT COUNT(*) FROM Posts p
   WHERE p.OwnerUserId = a.UserId
     AND p.PostTypeId = 1
     AND p.CreationDate > NOW() - INTERVAL '30 days') AS QuestionsLast30Days,
  (SELECT COUNT(*) FROM Comments c
   WHERE c.UserId = a.UserId
     AND c.CreationDate > NOW() - INTERVAL '60 days') AS CommentsLast60Days,
  (SELECT STRING_AGG(CONCAT(c.PostId, ':', c.Score), '|')
   FROM Posts p2
   LEFT JOIN Comments c ON c.PostId = p2.Id
   WHERE p2.OwnerUserId = a.UserId
     AND p2.CreationDate > NOW() - INTERVAL '90 days') AS RecentCommentScores,
  (SELECT COALESCE(ARRAY_AGG(DISTINCT t.TagName), ARRAY[]::varchar[])
   FROM Posts p3
   JOIN UNNEST(string_to_array(p3.Tags, '>')) AS t(TagName) ON TRUE
   WHERE p3.OwnerUserId = a.UserId) AS DistinctTagUniverse,
  (SELECT COUNT(*) FROM Badges b WHERE b.UserId = a.UserId AND b.Date > NOW() - INTERVAL '1 year') AS BadgesLastYear,
  (SELECT MAX(v.CreationDate) FROM Votes v WHERE v.UserId = a.UserId) AS LastVoteDate
FROM
  popular_authors a
  LEFT JOIN activity_enrichment ae ON a.UserId = ae.OwnerUserId
ORDER BY a.Reputation DESC, a.RecentTopQuestions DESC
LIMIT 100;