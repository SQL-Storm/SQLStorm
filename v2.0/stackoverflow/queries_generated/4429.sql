-- {"query": "4429.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1132} 
WITH
  UserPostCounts AS (
    SELECT
      OwnerUserId,
      COUNT(Id) AS TotalPosts
    FROM
      Posts
    WHERE
      OwnerUserId IS NOT NULL
    GROUP BY
      OwnerUserId
  ),
  PostScoreRank AS (
    SELECT
      Id,
      OwnerUserId,
      Score,
      ROW_NUMBER() OVER (PARTITION BY OwnerUserId ORDER BY Score DESC) AS ScoreRank
    FROM
      Posts
    WHERE
      PostTypeId = 1
  ),
  RecentEditDates AS (
    SELECT
      PostId,
      MAX(CreationDate) AS LastEditDate
    FROM
      PostHistory
    WHERE
      PostHistoryTypeId IN (4, 5, 6)
    GROUP BY
      PostId
  ),
  UserTopTags AS (
    SELECT
      p.OwnerUserId,
      t.TagName,
      COUNT(p.Id) AS TagPostCount,
      ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY COUNT(p.Id) DESC) AS TagRank
    FROM
      Posts p
      JOIN Tags t ON t.Id = ANY(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><'))
    WHERE
      p.PostTypeId = 1
      AND p.OwnerUserId IS NOT NULL
      AND t.TagName NOT LIKE '%-%'
    GROUP BY
      p.OwnerUserId,
      t.TagName
  )
SELECT
  u.Id AS UserId,
  u.DisplayName,
  COALESCE(upc.TotalPosts, 0) AS TotalPostsCreated,
  COALESCE(psr.Score, 0) AS TopQuestionScore,
  COALESCE(DATE_PART('year', AGE(u.LastAccessDate))) AS YearsSinceLastAccess,
  CASE
    WHEN u.WebsiteUrl IS NOT NULL THEN 'HasWebsite'
    WHEN u.AboutMe LIKE '%SQL%' THEN 'LikesSQL'
    ELSE 'NoSpecialIndicator'
  END AS UserIndicator,
  COALESCE(CONCAT(SUBSTRING(u.Location, 1, INSTR(u.Location, ',') - 1), ' (Approx)'), 'UnknownLocation') AS ApproximateLocation,
  COALESCE(
    (
      SELECT
        COUNT(*)
      FROM
        Comments c
      WHERE
        c.UserId = u.Id
        AND c.Score > 5
        AND c.CreationDate > u.CreationDate + INTERVAL '1 year'
    ),
    0
  ) AS HighScoreCommentsAfterFirstYear,
  COALESCE(pt.Name, 'NoPostType') AS MostFrequentPostType,
  CASE
    WHEN red.LastEditDate IS NOT NULL THEN red.LastEditDate
    ELSE u.CreationDate
  END AS EffectiveLastEditOrCreationDate,
  utt.TagName AS FavoriteTag,
  COUNT(DISTINCT ph.Id) AS PostHistoryCount
FROM
  Users u
LEFT JOIN
  UserPostCounts upc
  ON u.Id = upc.OwnerUserId
LEFT JOIN
  PostScoreRank psr
  ON u.Id = psr.OwnerUserId
  AND psr.ScoreRank = 1
LEFT JOIN
  (
    SELECT
      OwnerUserId,
      PostTypeId,
      COUNT(*) AS PostCount
    FROM
      Posts
    GROUP BY
      OwnerUserId,
      PostTypeId
  ) AS PostTypeCounts ON u.Id = PostTypeCounts.OwnerUserId
LEFT JOIN
  PostTypes pt
  ON PostTypeCounts.PostTypeId = pt.Id
  AND PostTypeCounts.PostCount = (
    SELECT
      MAX(PostCount)
    FROM
      (
        SELECT
          OwnerUserId,
          PostTypeId,
          COUNT(*) AS PostCount
        FROM
          Posts
        GROUP BY
          OwnerUserId,
          PostTypeId
      ) AS SubPostTypeCounts
    WHERE
      SubPostTypeCounts.OwnerUserId = u.Id
  )
LEFT JOIN
  RecentEditDates red
  ON u.Id = red.PostId
LEFT JOIN
  UserTopTags utt
  ON u.Id = utt.OwnerUserId
  AND utt.TagRank = 1
LEFT JOIN
  PostHistory ph
  ON u.Id = ph.UserId
  AND ph.PostId = u.Id -- Correlated subquery logic within outer join
WHERE
  u.Reputation > 1000
  AND u.DownVotes < u.UpVotes * 0.1
GROUP BY
  u.Id,
  u.DisplayName,
  upc.TotalPosts,
  psr.Score,
  u.LastAccessDate,
  u.WebsiteUrl,
  u.AboutMe,
  u.Location,
  pt.Name,
  red.LastEditDate,
  utt.TagName
ORDER BY
  u.Reputation DESC,
  YearsSinceLastAccess ASC
LIMIT 100;