WITH
  UserStats AS (
     SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.Location,
        u.CreationDate AS UserCreationDate,
        COALESCE(SUM(p.Score), 0) AS TotalPostScore,
        COUNT(p.Id) AS PostCount,
        (SELECT MAX(c.CreationDate) FROM Comments c WHERE c.UserId = u.Id) AS LastCommentDate,
        (SELECT COUNT(*) FROM Posts pp WHERE pp.OwnerUserId = u.Id AND pp.CreationDate >= TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '30' DAY) AS PostsLast30,
        MAX(p.LastActivityDate) AS LastActivityDate
     FROM Users u
     LEFT JOIN Posts p ON p.OwnerUserId = u.Id
     GROUP BY u.Id, u.DisplayName, u.Reputation, u.Location, u.CreationDate
  ),
  TopPosts AS (
     SELECT
        p.OwnerUserId,
        p.Title,
        p.Score,
        p.ViewCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.ViewCount DESC) AS rn
     FROM Posts p
     WHERE p.PostTypeId = 1
  ),
  Combined AS (
     SELECT
        us.UserId,
        us.DisplayName,
        us.Reputation,
        COALESCE(us.Location, 'Unknown') AS Location,
        us.UserCreationDate,
        us.TotalPostScore,
        us.PostCount,
        COALESCE(us.LastCommentDate, TIMESTAMP '1900-01-01') AS LastCommentDate,
        us.PostsLast30,
        tp.Title AS TopQuestionTitle,
        tp.Score AS TopScore
     FROM UserStats us
     LEFT JOIN TopPosts tp ON tp.OwnerUserId = us.UserId AND tp.rn = 1
  ),
  SystemRow AS (
     SELECT CAST(-1 AS INTEGER) AS UserId,
            'System' AS DisplayName,
            NULL AS Reputation,
            NULL AS Location,
            NULL AS UserCreationDate,
            NULL AS TotalPostScore,
            NULL AS PostCount,
            NULL AS LastCommentDate,
            NULL AS PostsLast30,
            'SystemTop' AS TopQuestionTitle,
            NULL AS TopScore
  ),
  SystemRow2 AS (
     SELECT CAST(-2 AS INTEGER) AS UserId,
            'Benchmark' AS DisplayName,
            NULL AS Reputation,
            NULL AS Location,
            NULL AS UserCreationDate,
            NULL AS TotalPostScore,
            NULL AS PostCount,
            NULL AS LastCommentDate,
            NULL AS PostsLast30,
            'BenchmarkTop' AS TopQuestionTitle,
            NULL AS TopScore
  )
SELECT
   UserId,
   DisplayName,
   Reputation,
   Location,
   UserCreationDate,
   TotalPostScore,
   PostCount,
   LastCommentDate,
   PostsLast30,
   TopQuestionTitle,
   TopScore
FROM Combined
UNION ALL
SELECT *
FROM SystemRow
UNION ALL
SELECT *
FROM SystemRow2
ORDER BY UserId
LIMIT 200;