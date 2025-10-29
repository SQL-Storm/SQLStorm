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
  WHERE p.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '90 days')
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
  LEFT JOIN LATERAL (
    SELECT TRIM(x) AS TagName
    FROM (
      SELECT UNNEST(
        CASE
          WHEN ta.Tags IS NOT NULL AND ta.Tags <> '' THEN string_to_array(ta.Tags, '<>')
          ELSE ARRAY[]::text[]
        END
      ) AS x
    ) AS unnested
  ) t ON TRUE
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
    tc.TagList,
    CASE
      WHEN r.Score > 100 THEN true
      WHEN r.ViewCount > 5000 THEN true
      WHEN POSITION('sql' IN LOWER(r.Title)) > 0 THEN true
      ELSE false
    END AS IsProminent
  FROM recent_activity r
  LEFT JOIN tag_combination tc ON tc.PostId = r.PostId
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
    cp.PostId,
    cp.Title,
    cp.LastActivityDate AS PostLastActivity,
    cp.Score AS PostScore,
    cp.ViewCount,
    ra.Tags AS PostTags,
    cp.TagList,
    cp.IsProminent
  FROM top_active_users cu
  LEFT JOIN complex_predicate cp ON cp.OwnerUserId = cu.UserId
  LEFT JOIN recent_activity ra ON ra.PostId = cp.PostId
  WHERE cp.IsProminent IS TRUE
  GROUP BY
    cu.UserId, cu.DisplayName, cu.Reputation, cu.CreationDate, cu.LastAccessDate,
    cu.Location, cu.Views, cu.UpVotes, cu.DownVotes, cu.AccountId,
    cu.PostCount, cu.ScoreSum, cu.LastPostDate,
    cp.PostId, cp.Title, cp.LastActivityDate, cp.Score, cp.ViewCount,
    ra.Tags, cp.TagList, cp.IsProminent
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