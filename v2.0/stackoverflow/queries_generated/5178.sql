-- {"query": "5178.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 839} 
WITH RankedPosts AS (
  SELECT
    p.Id,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.Tags,
    p.PostTypeId,
    p.AnswerCount,
    p.CommentCount,
    p.LastActivityDate,
    p.FavoriteCount,
    p.ContentLicense,
    u.Reputation,
    u.DisplayName,
    u.Location,
    u.AccountId,
    ROW_NUMBER() OVER (
      PARTITION BY p.PostTypeId
      ORDER BY
        CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END DESC,
        p.LastActivityDate DESC,
        p.ViewCount DESC
    ) AS rn
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN PostLinks pl ON p.Id = pl.PostId
  LEFT JOIN PostLinks pl2 ON pl.RelatedPostId = pl2.PostId
  WHERE p.ParentId IS NULL
    AND p.CreationDate >= NOW() - INTERVAL '1 year'
),
Filtered AS (
  SELECT *
  FROM RankedPosts
  WHERE rn <= 100
),
Aggregated AS (
  SELECT
    p.TagName AS Tag,
    COUNT(*) AS PostCount,
    AVG(p.Score) AS AvgScore,
    SUM(p.ViewCount) AS TotalViews,
    MAX(p.LastActivityDate) AS LastActive
  FROM (
    SELECT
      TRIM(both '><' FROM UNNEST(string_to_array(substr(p.Tags, 2, length(p.Tags)-2), '><'))) AS TagName,
      p.Score,
      p.ViewCount,
      p.LastActivityDate
    FROM Filtered p
    WHERE p.Tags IS NOT NULL
  ) t
  GROUP BY TagName
),
ComplexQuery AS (
  SELECT
    p.Id,
    p.Title,
    p.CreationDate,
    p.LastActivityDate,
    p.ViewCount,
    p.Score,
    p.OwnerUserId,
    COALESCE(vv.TotalUp, 0) - COALESCE(vv.TotalDown, 0) AS NetVotes,
    u.Reputation,
    u.DisplayName,
    CASE
      WHEN p.PostTypeId = 1 THEN 'Question'
      WHEN p.PostTypeId = 2 THEN 'Answer'
      ELSE 'Other'
    END AS PostTypeLabel,
    CASE
      WHEN p.OwnerUserId IS NOT NULL THEN
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = p.OwnerUserId AND b.Class = 1)
      ELSE 0
    END AS GoldBadgesForOwner,
    (SELECT JSON_AGG(JSON_BUILD_OBJECT('VoteType', vt.Name, 'Count', COUNT(*) ))
     FROM Votes vo
     JOIN VoteTypes vt ON vo.VoteTypeId = vt.Id
     WHERE vo.PostId = p.Id
     GROUP BY vo.PostId) AS VoteBreakdown
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN (
    SELECT PostId, 
           SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUp,
           SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDown
    FROM Votes
    GROUP BY PostId
  ) vv ON p.Id = vv.PostId
  WHERE p.Id IN (SELECT Id FROM Filtered)
),
Windowed AS (
  SELECT *,
         ROW_NUMBER() OVER (ORDER BY LastActivityDate DESC, ViewCount DESC) AS seq
  FROM ComplexQuery
)
SELECT
  Id,
  Title,
  CreationDate,
  LastActivityDate,
  ViewCount,
  Score,
  NetVotes,
  Reputation,
  DisplayName,
  PostTypeLabel,
  GoldBadgesForOwner,
  VoteBreakdown
FROM Windowed
WHERE seq <= 500
ORDER BY LastActivityDate DESC, ViewCount DESC;