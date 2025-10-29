WITH RecentTopTags AS (
  SELECT
    t.TagName,
    COUNT(p.Id) AS QuestionCount,
    AVG(p.Score) AS AvgScore,
    SUM(p.ViewCount) AS TotalViews,
    MAX(p.CreationDate) AS LastCreated
  FROM Posts p
  JOIN PostTypes pt ON p.PostTypeId = pt.Id
  JOIN Tags t ON POSITION(CONCAT(',', t.Id, ',') IN CONCAT(',', p.Tags, ',')) > 0
  WHERE pt.Name = 'Question'
    AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30 days'
  GROUP BY t.TagName
),
TagEngagement AS (
  SELECT
    rt.TagName,
    rt.QuestionCount,
    rt.AvgScore,
    rt.TotalViews,
    ROW_NUMBER() OVER (ORDER BY rt.TotalViews DESC, rt.AvgScore DESC) AS rn
  FROM RecentTopTags rt
),
TopTags AS (
  SELECT TagName
  FROM TagEngagement
  WHERE rn <= 10
),
UserActivity AS (
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
    COALESCE(bg.TotalBadges, 0) AS BadgeCount,
    COALESCE(vw.TotalVotes, 0) AS VoteCount
  FROM Users u
  LEFT JOIN (
    SELECT UserId, COUNT(*) AS TotalBadges
    FROM Badges
    GROUP BY UserId
  ) bg ON bg.UserId = u.Id
  LEFT JOIN (
    SELECT UserId, COUNT(*) AS TotalVotes
    FROM Votes
    WHERE VoteTypeId IN (2, 3)
    GROUP BY UserId
  ) vw ON vw.UserId = u.Id
  WHERE u.Reputation > 100
),
PostsForTop AS (
  SELECT
    p.Id,
    p.Title,
    p.Tags,
    p.OwnerUserId,
    p.CreationDate,
    p.Score,
    p.ViewCount
  FROM Posts p
  JOIN TopTags tt ON POSITION(CONCAT(',', tt.TagName, ',') IN CONCAT(',', p.Tags, ',')) > 0
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '60 days'
),
CorrelationCTE AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    p.OwnerUserId,
    u.Id AS OwnerUserId_FromUsers,
    u.DisplayName AS OwnerName,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn_owner
  FROM PostsForTop p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
)
SELECT
  pc.PostId,
  pc.Title,
  pc.Tags,
  pc.Score,
  pc.ViewCount,
  pc.CreationDate,
  pc.OwnerName,
  at.UserId AS ActivityUserId,
  at.DisplayName AS ActivityUserName,
  at.Reputation AS ActivityUserRep,
  at.BadgeCount,
  at.VoteCount,
  SUM(pc.Score) OVER (PARTITION BY pc.OwnerUserId ORDER BY pc.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS RunningOwnerScore,
  (SELECT COUNT(*) FROM Posts q
   WHERE q.OwnerUserId = pc.OwnerUserId
     AND q.PostTypeId = 1
     AND q.CreationDate >= pc.CreationDate - INTERVAL '90 days'
     AND q.CreationDate <= pc.CreationDate
     AND q.Score > pc.Score) AS RecentHigherScoredPosts
FROM CorrelationCTE pc
LEFT JOIN UserActivity at ON pc.OwnerUserId = at.UserId
ORDER BY pc.CreationDate DESC
LIMIT 100;