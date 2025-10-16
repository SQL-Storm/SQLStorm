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
    tg.TagName,
    SUM(p.Score) AS TotalScore,
    COUNT(*) AS QCount
  FROM Tags tg
  JOIN Posts p ON p.Id = tg.ExcerptPostId
  WHERE tg.TagName IS NOT NULL
  GROUP BY tg.TagName
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
    pl.PostId,
    pl.RelatedPostId,
    lt.Id AS LinkTypeId,
    lt.Name AS LinkTypeName
  FROM PostLinks pl
  JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
  WHERE pl.LinkTypeId IS NOT NULL
),
ComplexCalc AS (
  SELECT
    pl.PostId,
    pl.RelatedPostId,
    lt.Id AS LinkTypeId,
    lt.Name AS LinkTypeName,
    p.Title AS PostTitle,
    p.OwnerUserId,
    p.ViewCount AS Views,
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
  LEFT JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
  GROUP BY pl.PostId, pl.RelatedPostId, lt.Id, lt.Name, p.Title, p.OwnerUserId, p.ViewCount, p.Score, p.CreationDate
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
  mc.PostTitle AS RelatedPostTitle,
  mc.LinkTypeName,
  v.TotalVotes,
  rh.LastActivityDate
FROM RecentHot rh
LEFT JOIN ActiveUsers au ON au.Id = rh.OwnerUserId AND au.rn = 1
LEFT JOIN (
  SELECT
    v.PostId,
    SUM(CASE WHEN v.VoteTypeId IN (2,3) THEN 1 ELSE 0 END) AS TotalVotes
  FROM Votes v
  GROUP BY v.PostId
) v ON v.PostId = rh.PostId
LEFT JOIN ComplexCalc mc ON mc.PostId = rh.PostId
ORDER BY rh.LastActivityDate DESC
LIMIT 200;