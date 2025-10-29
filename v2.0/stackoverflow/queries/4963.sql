-- {"query": "4963.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1885}
WITH
  RankedUserPosts AS (
    SELECT
      p.OwnerUserId,
      p.Id AS PostId,
      p.PostTypeId,
      p.Score,
      p.ViewCount,
      p.CreationDate,
      ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn,
      RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS score_rank
    FROM Posts p
    WHERE
      p.PostTypeId IN (1, 2) AND p.OwnerUserId IS NOT NULL
  ),
  UserEngagement AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      u.UpVotes AS UserUpVotes,
      u.DownVotes AS UserDownVotes,
      COUNT(DISTINCT pu.PostId) AS TotalPosts,
      SUM(pu.Score) AS TotalScore,
      AVG(CAST(pu.ViewCount AS DECIMAL)) AS AvgViewCount,
      MAX(pu.CreationDate) AS LastPostDate,
      COUNT(DISTINCT CASE WHEN pu.rn <= 5 THEN pu.PostId ELSE NULL END) AS Top5Posts,
      COUNT(DISTINCT CASE WHEN pu.score_rank <= 3 THEN pu.PostId ELSE NULL END) AS Top3ScoringPosts,
      SUM(CASE WHEN pht.PostHistoryTypeId = 2 THEN 1 ELSE 0 END) AS BodyEdits,
      SUM(CASE WHEN pht.PostHistoryTypeId = 4 THEN 1 ELSE 0 END) AS TitleEdits
    FROM Users u
    LEFT JOIN RankedUserPosts pu
      ON u.Id = pu.OwnerUserId
    LEFT JOIN PostHistory pht
      ON pu.PostId = pht.PostId AND pht.PostHistoryTypeId IN (2, 4)
    WHERE
      u.Id > 0 AND u.CreationDate BETWEEN TIMESTAMP '2010-01-01' AND TIMESTAMP '2023-01-01'
    GROUP BY
      u.Id,
      u.DisplayName,
      u.Reputation,
      u.UpVotes,
      u.DownVotes,
      u.CreationDate
  ),
  PostSummary AS (
    SELECT
      p.Id AS PostId,
      p.Title,
      pt.Name AS PostTypeName,
      u.DisplayName AS OwnerDisplayName,
      p.CreationDate,
      p.Score,
      p.ViewCount,
      p.AnswerCount,
      p.CommentCount,
      p.FavoriteCount,
      p.ClosedDate,
      CASE WHEN p.ClosedDate IS NOT NULL THEN CAST((CAST(TIMESTAMP '2024-10-01 12:34:56' AS TIMESTAMP) - CAST(p.ClosedDate AS TIMESTAMP)) AS INTERVAL) END AS DaysSinceClosed_interval,
      -- also provide numeric days difference in a dialect-neutral way using EXTRACT(epoch ...)
      CASE WHEN p.ClosedDate IS NOT NULL THEN EXTRACT(epoch FROM (CAST(TIMESTAMP '2024-10-01 12:34:56' AS TIMESTAMP) - CAST(p.ClosedDate AS TIMESTAMP)))/86400 ELSE NULL END AS DaysSinceClosed,
      CAST(
        REPLACE(
          REPLACE(
            REPLACE(
              p.Tags,
              '<',
              ''
            ),
            '>',
            ' '
          ),
          ' ',
          ','
        ) AS VARCHAR(4000)
      ) AS TagsCSV,
      COALESCE(p.OwnerUserId, -1) AS OwnerId,
      CASE
        WHEN p.OwnerUserId IS NULL THEN 'Community'
        ELSE u.DisplayName
      END AS DisplayOwnerName,
      ROW_NUMBER() OVER (ORDER BY p.CreationDate DESC) AS PostCreationRank
    FROM Posts p
    JOIN PostTypes pt
      ON p.PostTypeId = pt.Id
    LEFT JOIN Users u
      ON p.OwnerUserId = u.Id
    WHERE
      p.PostTypeId IN (1, 2) AND p.CreationDate >= (CAST(TIMESTAMP '2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '5' YEAR)
  )
SELECT
  ps.PostId,
  ps.Title,
  ps.PostTypeName,
  ps.OwnerDisplayName,
  ps.CreationDate,
  ps.Score,
  ps.ViewCount,
  ps.AnswerCount,
  ps.CommentCount,
  ps.FavoriteCount,
  ps.ClosedDate,
  ps.DaysSinceClosed,
  ps.TagsCSV,
  ps.PostCreationRank,
  ue.TotalPosts,
  ue.TotalScore,
  ue.AvgViewCount,
  ue.LastPostDate,
  ue.Top5Posts,
  ue.Top3ScoringPosts,
  ue.BodyEdits,
  ue.TitleEdits,
  CASE
    WHEN ue.Reputation > 100000 THEN 'High'
    WHEN ue.Reputation > 10000 THEN 'Medium'
    ELSE 'Low'
  END AS ReputationLevel,
  (
    SELECT
      COUNT(c.Id)
    FROM Comments c
    WHERE
      c.PostId = ps.PostId AND c.CreationDate >= ps.CreationDate AND c.CreationDate < (ps.CreationDate + INTERVAL '1' HOUR)
  ) AS CommentsInFirstHour,
  (
    SELECT
      COUNT(ph.Id)
    FROM PostHistory ph
    WHERE
      ph.PostId = ps.PostId AND ph.PostHistoryTypeId IN (2, 4, 6) AND ph.CreationDate >= ps.CreationDate AND ph.CreationDate < (ps.CreationDate + INTERVAL '7' DAY)
  ) AS EditsInFirstWeek,
  CASE
    WHEN LOWER(ps.Title) LIKE '%how%' THEN 'How-To'
    WHEN LOWER(ps.Title) LIKE '%why%' THEN 'Why-Question'
    ELSE 'Other'
  END AS TitleCategory,
  CASE
    WHEN ps.FavoriteCount > 100 AND ps.Score > 50 THEN 'Highly Valued'
    WHEN ps.FavoriteCount > 50 OR ps.Score > 20 THEN 'Moderately Valued'
    ELSE 'Standard'
  END AS ValueCategory,
  CONCAT(ps.OwnerDisplayName, '-', ps.PostTypeName) AS OwnerPostType,
  (ps.PostId % 10) AS PostIdModulo10,
  ue.UserId AS EngagementUserId,
  COALESCE(
    (
      SELECT
        SUM(v.VoteTypeId)
      FROM Votes v
      WHERE
        v.PostId = ps.PostId AND v.VoteTypeId IN (2, 3) AND v.CreationDate BETWEEN ps.CreationDate AND (ps.CreationDate + INTERVAL '30' DAY)
    ),
    0
  ) + COALESCE(
    (
      SELECT
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE -1 END)
      FROM Votes v
      WHERE
        v.PostId = ps.PostId AND v.VoteTypeId IN (2, 3) AND v.CreationDate > (ps.CreationDate + INTERVAL '30' DAY)
    ),
    0
  ) AS AdjustedScore,
  CASE WHEN ps.TagsCSV LIKE '%sql%' THEN 1 ELSE 0 END AS HasSqlTag
FROM PostSummary ps
LEFT JOIN UserEngagement ue
  ON ps.OwnerId = ue.UserId
WHERE
  ps.Score > 0
  AND ps.ViewCount > 100
  AND (
    ue.TotalPosts > 50 OR ue.Reputation > 5000
  )
  AND NOT EXISTS (
    SELECT
      1
    FROM PostLinks pl
    WHERE
      pl.PostId = ps.PostId AND pl.LinkTypeId = 3
  )
UNION ALL
SELECT
  NULL AS PostId,
  NULL AS Title,
  NULL AS PostTypeName,
  NULL AS OwnerDisplayName,
  NULL AS CreationDate,
  NULL AS Score,
  NULL AS ViewCount,
  NULL AS AnswerCount,
  NULL AS CommentCount,
  NULL AS FavoriteCount,
  NULL AS ClosedDate,
  NULL AS DaysSinceClosed,
  NULL AS TagsCSV,
  NULL AS PostCreationRank,
  NULL AS TotalPosts,
  NULL AS TotalScore,
  NULL AS AvgViewCount,
  NULL AS LastPostDate,
  NULL AS Top5Posts,
  NULL AS Top3ScoringPosts,
  NULL AS BodyEdits,
  NULL AS TitleEdits,
  NULL AS ReputationLevel,
  NULL AS CommentsInFirstHour,
  NULL AS EditsInFirstWeek,
  NULL AS TitleCategory,
  NULL AS ValueCategory,
  NULL AS OwnerPostType,
  NULL AS PostIdModulo10,
  NULL AS EngagementUserId,
  NULL AS AdjustedScore,
  NULL AS HasSqlTag
FROM PostTypes pt
WHERE
  pt.Id = 99;