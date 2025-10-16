-- {"query": "6093.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 821} 
WITH
RecentHot AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.OwnerUserId,
    p.PostTypeId,
    p.LastActivityDate,
    ROW_NUMBER() OVER (ORDER BY p.LastActivityDate DESC, p.Score DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1 -- Questions
    AND p.ClosedDate IS NULL
),
TopTags AS (
  SELECT
    t.TagName,
    SUM(p.Score) AS TotalScore,
    COUNT(*) AS QCount
  FROM Tags tg
  JOIN Posts p ON p.Id = tg.ExcerptPostId
  JOIN (SELECT TagName FROM Tags WHERE TagName IS NOT NULL) t ON 1=1
  GROUP BY t.TagName
),
ActiveUsers AS (
  SELECT
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY u.LastAccessDate DESC) AS rn
  FROM Users u
  WHERE u.Reputation > 100
),
MutualRef AS (
  SELECT
    hl.PostId,
    hl.RelatedPostId,
    lt.Id AS LinkTypeId,
    lt.Name AS LinkTypeName
  FROM PostLinks hl
  JOIN LinkTypes lt ON lt.Id = hl.LinkTypeId
  WHERE hl.LinkId IS NULL
),
ComplexCalc AS (
  SELECT
    rp.PostId,
    rp.RelatedPostId,
    rp.LinkTypeId,
    rp.LinkTypeName,
    p.Title AS PostTitle,
    p.OwnerUserId,
    p.Views,
    p.Score,
    p.CreationDate,
    (p.Score * 1.0) / NULLIF(p.ViewCount, 0) AS ScorePerView,
    CASE
      WHEN p.ViewCount > 1000 THEN 'HighExposure'
      WHEN p.ViewCount > 100 THEN 'MediumExposure'
      ELSE 'LowExposure'
    END AS ExposureBand,
    STRING_AGG(DISTINCT tg.TagName, ',') AS AllTags
  FROM PostLinks pl
  JOIN Posts p ON p.Id = pl.PostId
  JOIN Posts rp ON rp.Id = pl.RelatedPostId
  LEFT JOIN Tags tg ON tg.ExcerptPostId = rp.Id
  GROUP BY rp.PostId, rp.RelatedPostId, rp.LinkTypeId, rp.LinkTypeName, p.Title, p.OwnerUserId, p.Views, p.Score, p.CreationDate
)
SELECT
  rh.PostId,
  rh.Title AS QuestionTitle,
  rh.CreationDate AS QuestionCreated,
  rh.Score AS QuestionScore,
  rh.ViewCount,
  rh.Tags,
  au.DisplayName AS OwnerDisplayName,
  au.Reputation AS OwnerReputation,
  au.LastAccessDate AS OwnerLastActive,
  mc.AllTags AS RelatedTags,
  mc.ExposureBand,
  mc.ScorePerView,
  mc.Title AS RelatedPostTitle,
  mc.LinkTypeName,
  v.TotalVotes
FROM RecentHot rh
LEFT JOIN ActiveUsers au ON au.Id = rh.OwnerUserId AND au.rn = 1
LEFT JOIN (
  SELECT
    cr.PostId,
    SUM(CASE WHEN vt.VoteTypeId IN (2,3) THEN 1 ELSE 0 END) AS TotalVotes
  FROM Votes v
  JOIN Posts cr ON cr.Id = v.PostId
  JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
  GROUP BY cr.PostId
) v ON v.PostId = rh.PostId
LEFT JOIN ComplexCalc mc ON mc.PostId = rh.PostId
ORDER BY rh.LastActivityDate DESC
LIMIT 200;