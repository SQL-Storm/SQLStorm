-- {"query": "5389.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 764}
WITH TopUsers AS (
  SELECT
    u.Id,
    u.DisplayName,
    u.Reputation,
    COUNT(p.Id) AS PostsCreated,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesReceived,
    SUM(CASE WHEN v.VoteTypeId IN (10,12,14) THEN 1 ELSE 0 END) AS NegativeVotes,
    MAX(p.CreationDate) AS LastPostDate
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation
),
TrendingTags AS (
  SELECT
    t.TagName,
    COUNT(*) AS TagPostCount,
    AVG(p.Score) AS AvgPostScore,
    MAX(p.LastActivityDate) AS LastActive
  FROM Posts p,
       UNNEST(string_to_array(substring(p.Tags FROM 2 FOR (char_length(p.Tags)-2)), '><')) AS t(TagName)
  GROUP BY t.TagName
),
RecentActivity AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.PostTypeId,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.OwnerUserId,
    p.CreationDate,
    p.LastActivityDate,
    CASE
      WHEN p.PostTypeId = 1 THEN 'Question'
      WHEN p.PostTypeId = 2 THEN 'Answer'
      ELSE 'Other'
    END AS PostKind
  FROM Posts p
  WHERE p.LastActivityDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30 days')
),
LinkedDynamics AS (
  SELECT
    pl.PostId,
    pl.RelatedPostId,
    lt.Name AS LinkTypeName,
    p2.Title AS RelatedTitle
  FROM PostLinks pl
  JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
  JOIN Posts p2 ON pl.RelatedPostId = p2.Id
  WHERE lt.Id IN (1,3)
),
WindowedStats AS (
  SELECT
    r.PostId,
    r.Title,
    r.OwnerUserId,
    r.CreationDate,
    r.LastActivityDate,
    r.Score,
    r.ViewCount,
    RANK() OVER (PARTITION BY r.OwnerUserId ORDER BY r.LastActivityDate DESC) AS UserPostRank
  FROM RecentActivity r
)
SELECT
  t1.DisplayName AS TopAuthor,
  t1.Reputation AS AuthorReputation,
  t1.PostsCreated,
  t1.UpvotesReceived,
  t1.NegativeVotes,
  t2.TagName AS TrendingTag,
  t2.TagPostCount,
  t2.AvgPostScore,
  t2.LastActive,
  w.PostId,
  ra.Title AS PostTitle,
  ra.PostTypeId AS PostTypeId,
  ra.Tags AS PostTags,
  ra.OwnerUserId AS PostOwnerUserId,
  ra.PostKind,
  ra.Score AS PostScore,
  ra.ViewCount AS PostViews,
  ra.CreationDate AS PostCreatedAt,
  ra.LastActivityDate AS PostActiveAt,
  w.UserPostRank AS RankAmongAuthor,
  ld.RelatedPostId,
  ld.LinkTypeName,
  ld.RelatedTitle
FROM TopUsers t1
LEFT JOIN LATERAL (
  SELECT tt.TagName, tt.TagPostCount, tt.AvgPostScore, tt.LastActive
  FROM TrendingTags tt
  ORDER BY tt.TagPostCount DESC
  LIMIT 1
) t2 ON TRUE
LEFT JOIN WindowedStats w ON w.OwnerUserId = t1.Id
LEFT JOIN LinkedDynamics ld ON ld.PostId = w.PostId
LEFT JOIN RecentActivity ra ON ra.PostId = w.PostId
ORDER BY t1.Reputation DESC, t1.PostsCreated DESC
LIMIT 100;