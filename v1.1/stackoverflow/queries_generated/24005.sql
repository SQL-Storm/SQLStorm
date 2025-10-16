-- {"query": "24005.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 3896} 

WITH
  -- 1. explode <tag><tag>… strings into one column per tag
  PostTagRows AS (
    SELECT p.Id                                 AS PostId,
           p.OwnerUserId,
           p.Score,
           REPLACE(REPLACE(t.tag, '>', ''), '<', '') AS Tag
    FROM Posts p
    CROSS JOIN LATERAL regexp_split_to_table(p.Tags, '><') AS t(tag)
    WHERE p.PostTypeId = 1
  ),

  -- 2. aggregate per-question‑tag per user
  TagStats AS (
    SELECT pt.OwnerUserId,
           pt.Tag,
           COUNT(*)                AS QCount,
           SUM(pt.Score)           AS TagScore,
           AVG(pt.Score)::numeric(10,2) AS AvgScore,
           MAX(pt.Score)           AS MaxScore
    FROM PostTagRows pt
    GROUP BY pt.OwnerUserId, pt.Tag
  ),

  -- 3. rank tags for every user
  RankedTags AS (
    SELECT ts.*,
           RANK() OVER (PARTITION BY ts.OwnerUserId ORDER BY ts.TagScore DESC) AS TagRank
    FROM TagStats ts
  ),

  -- 4. keep the top‑scoring tag of each user
  TopTagPerUser AS (
    SELECT OwnerUserId, Tag, TagScore, QCount
    FROM RankedTags
    WHERE TagRank = 1
  ),

  -- 5. collectible user metadata – correlated sub‑queries for totals
  UserMeta AS (
    SELECT u.Id                                     AS UserId,
           u.DisplayName,
           u.Reputation,
           COALESCE((SELECT COUNT(*) FROM Posts p2
                     WHERE p2.OwnerUserId = u.Id AND p2.PostTypeId = 1),0) AS TotalQ,
           COALESCE((SELECT COUNT(*) FROM Posts p2
                     WHERE p2.OwnerUserId = u.Id AND p2.PostTypeId = 2),0) AS TotalA
    FROM Users u
    WHERE u.CreationDate >= '2022-01-01'
  ),

  -- 6. vote totals per post, cast numerically for later join
  VoteSummaries AS (
    SELECT v.PostId,
           SUM(CASE WHEN v.VoteTypeId = 2 THEN 1
                    WHEN v.VoteTypeId = 3 THEN -1
                    ELSE 0 END) AS VoteSum
    FROM Votes v
    GROUP BY v.PostId
  ),

  -- 7. users with pending close‑vote “duplicate” history – set‑operator demo
  CloseVoteUsers AS (
    SELECT DISTINCT v.UserId
    FROM Votes v
    JOIN PostHistory ph ON ph.PostId = v.PostId
    WHERE ph.PostHistoryTypeId = 10
      AND ph.Comment LIKE '%duplicate%'
  )
SELECT um.UserId,
       um.DisplayName,
       um.Reputation,
       um.TotalQ,
       um.TotalA,
       tt.Tag,
       tt.TagScore,
       tt.QCount,
       COALESCE(vsum.VoteSum,0) AS PostVoteSum,
       CASE WHEN tt.Tag IN ('javascript','python') THEN 'CoolTag'
            ELSE 'OtherTag' END AS TagMood,
       CASE WHEN um.Reputation IS NULL THEN 0
            ELSE um.Reputation + 1000 END AS ReputationAdj
FROM UserMeta um
LEFT JOIN TopTagPerUser tt ON um.UserId = tt.OwnerUserId
LEFT JOIN (
    SELECT pt.OwnerUserId,
           pt.Tag,
           SUM(vs.VoteSum) AS VoteSum
    FROM PostTagRows pt
    JOIN VoteSummaries vs ON vs.PostId = pt.PostId
    GROUP BY pt.OwnerUserId, pt.Tag
) vsum ON vsum.OwnerUserId = um.UserId AND vsum.Tag = tt.Tag
WHERE um.Reputation > 1000

UNION ALL

SELECT u.Id,
       u.DisplayName,
       0                      AS Reputation,
       0                      AS TotalQ,
       0                      AS TotalA,
       NULL                   AS Tag,
       0                      AS TagScore,
       0                      AS QCount,
       0                      AS PostVoteSum,
       NULL                   AS TagMood,
       0                      AS ReputationAdj
FROM Users u
JOIN CloseVoteUsers cvu ON u.Id = cvu.UserId
WHERE u.Reputation < 500

ORDER BY ReputationAdj DESC,
         UserId ASC
LIMIT 100;
