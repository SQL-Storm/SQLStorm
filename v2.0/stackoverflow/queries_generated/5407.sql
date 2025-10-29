-- {"query": "5407.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 904} 
WITH top_active_users AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Location,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.AccountId,
    COUNT(p.Id) AS PostCount,
    SUM(p.Score) AS ScoreSum,
    MAX(p.CreationDate) AS LastPostDate
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  WHERE u.Reputation >= 1000
  GROUP BY
    u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate,
    u.Location, u.Views, u.UpVotes, u.DownVotes, u.AccountId
),
recent_activity AS (
  SELECT
    p.Id AS PostId,
    p.OwnerUserId,
    p.Title,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.PostTypeId,
    CASE
      WHEN p.PostTypeId = 1 THEN 'Question'
      WHEN p.PostTypeId = 2 THEN 'Answer'
      ELSE 'Other'
    END AS PostKind,
    COALESCE(vs.TotalUp, 0) AS TotalUpFromVotes,
    COALESCE(vs.TotalDown, 0) AS TotalDownFromVotes
  FROM Posts p
  LEFT JOIN (
    SELECT
      PostId,
      SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUp,
      SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDown
    FROM Votes
    GROUP BY PostId
  ) vs ON vs.PostId = p.Id
  WHERE p.CreationDate >= NOW() - INTERVAL '90 days'
    AND p.CommunityOwnedDate IS NULL
),
tag_combination AS (
  SELECT
    ta.PostId,
    ta.OwnerUserId,
    ta.Title,
    ta.Tags,
    STRING_AGG(t.TagName, ',') AS TagList
  FROM recent_activity ta
  LEFT JOIN UNNEST(CASE WHEN ta.Tags IS NOT NULL THEN string_to_array(ta.Tags, '<>') ELSE ARRAY[] END) AS t(TagName)
    ON TRUE
  GROUP BY ta.PostId, ta.OwnerUserId, ta.Title, ta.Tags
),
complex_predicate AS (
  SELECT
    r.PostId,
    r.OwnerUserId,
    r.Title,
    r.LastActivityDate,
    r.Score,
    r.ViewCount,
    r.TagList,
    CASE
      WHEN r.Score > 100 THEN true
      WHEN r.ViewCount > 5000 THEN true
      WHEN POSITION('sql' IN LOWER(r.Title)) > 0 THEN true
      ELSE false
    END AS IsProminent
  FROM recent_activity r
),
final AS (
  SELECT
    cu.UserId,
    cu.DisplayName,
    cu.Reputation,
    cu.CreationDate,
    cu.LastAccessDate,
    cu.Location,
    cu.Views,
    cu.UpVotes,
    cu.DownVotes,
    cu.AccountId,
    cu.PostCount,
    cu.ScoreSum,
    cu.LastPostDate,
    ca.PostId,
    ca.Title,
    ca.LastActivityDate AS PostLastActivity,
    ca.Score AS PostScore,
    ca.ViewCount,
    ca.Tags AS PostTags,
    ca.TagList,
    cp.IsProminent
  FROM top_active_users cu
  LEFT JOIN complex_predicate ca ON ca.OwnerUserId = cu.UserId
  LEFT JOIN tag_combination tc ON tc.PostId = ca.PostId
  WHERE cp.IsProminent IS TRUE
)
SELECT
  UserId,
  DisplayName,
  Reputation,
  CreationDate,
  LastAccessDate,
  Location,
  Views,
  UpVotes,
  DownVotes,
  AccountId,
  PostCount,
  ScoreSum,
  LastPostDate,
  PostId,
  Title,
  PostLastActivity,
  PostScore,
  ViewCount,
  PostTags,
  TagList,
  IsProminent
FROM final
ORDER BY Reputation DESC NULLS LAST, LastPostDate DESC
LIMIT 200;