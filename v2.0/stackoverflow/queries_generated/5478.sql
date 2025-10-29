-- {"query": "5478.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 788} 
WITH TopUsers AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.AccountId,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.UpVotes DESC, u.LastAccessDate DESC) AS rn
  FROM Users u
),
RecentActivity AS (
  SELECT
    u.Id AS UserId,
    MAX(p.LastActivityDate) AS LastActivity,
    MAX(p.ViewCount) AS MaxViews,
    COUNT(p.Id) AS PostCount
  FROM Posts p
  JOIN Users u ON p.OwnerUserId = u.Id
  GROUP BY u.Id
),
TagStats AS (
  SELECT
    t.TagName,
    COUNT(p.Id) AS PostCount,
    SUM(p.Score) AS ScoreSum,
    AVG(p.Score) AS AvgScore
  FROM Posts p
  JOIN Tags tg ON tg.Id = (
    SELECT Id FROM Tags t2
    WHERE t2.TagName = ANY(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><'))
    LIMIT 1
  )
  WHERE p.PostTypeId = 1
  GROUP BY t.TagName
),
ComplexPost AS (
  SELECT
    p.Id,
    p.Title,
    p.Body,
    p.Tags,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    p.OwnerUserId,
    p.AcceptedAnswerId,
    p.CommentCount,
    p.LastActivityDate,
    p.PostTypeId,
    p.FavoriteCount,
    p.ParentId,
    p.LastEditorUserId,
    p.LastEditDate,
    p.ContentLicense
  FROM Posts p
  LEFT JOIN PostLinks pl ON pl.PostId = p.Id
  LEFT JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
  WHERE p.PostTypeId IN (1,2)
    AND (p.ViewCount > 0 OR p.Score <> 0)
),
Windowed AS (
  SELECT
    c.Id,
    c.Title,
    c.OwnerUserId,
    c.LastActivityDate,
    c.Score,
    ROW_NUMBER() OVER (PARTITION BY c.OwnerUserId ORDER BY c.LastActivityDate DESC) AS rn_owner
  FROM ComplexPost c
),
Joined AS (
  SELECT
    tu.UserId,
    tu.DisplayName,
    ru.LastActivity AS LastPostActivity,
    ru.MaxViews AS MaxPostViews,
    ru.PostCount AS PostCountByUser,
    t.TagName,
    t.PostCount AS TagPostCount,
    w.Id AS PostId,
    w.Title,
    w.LastActivityDate,
    w.Score,
    w.ViewCount
  FROM TopUsers tu
  LEFT JOIN RecentActivity ru ON ru.UserId = tu.UserId
  LEFT JOIN (
    SELECT
      tg.TagName,
      COUNT(p.Id) AS PostCount
    FROM Posts p
    JOIN Tags tg ON TRUE
    WHERE p.PostTypeId = 1
    GROUP BY tg.TagName
  ) t ON TRUE
  LEFT JOIN Windowed w ON w.OwnerUserId = tu.UserId
  WHERE tu.rn <= 100
)
SELECT
  joined.UserId,
  joined.DisplayName,
  joined.LastPostActivity,
  joined.MaxPostViews,
  joined.PostCountByUser,
  joined.TagName,
  joined.TagPostCount,
  joined.PostId,
  joined.Title,
  joined.LastPostActivity AS ActivityDate,
  joined.Score,
  joined.ViewCount
FROM Joined joined
ORDER BY joined.PostCountByUser DESC NULLS LAST, joined.LastPostActivity DESC NULLS LAST
LIMIT 200;