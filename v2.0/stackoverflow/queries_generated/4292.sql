-- {"query": "4292.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1410} 

WITH
  RankedUserActivity AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      COUNT(DISTINCT p.Id) AS PostCount,
      COUNT(DISTINCT c.Id) AS CommentCount,
      SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
      SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
      ROW_NUMBER() OVER (
        ORDER BY
          u.Reputation DESC,
          COUNT(DISTINCT p.Id) DESC
      ) AS ReputationRank,
      DENSE_RANK() OVER (
        PARTITION BY
          DATE_PART('year', u.CreationDate)
        ORDER BY
          u.Reputation DESC
      ) AS YearlyReputationRank
    FROM
      Users AS u
    LEFT JOIN
      Posts AS p
      ON u.Id = p.OwnerUserId
    LEFT JOIN
      Comments AS c
      ON u.Id = c.UserId
    LEFT JOIN
      Votes AS v
      ON u.Id = v.UserId
    WHERE
      u.CreationDate >= '2010-01-01'
      AND u.Location IS NOT NULL
      AND u.AboutMe LIKE '%SQL%'
    GROUP BY
      u.Id,
      u.DisplayName,
      u.Reputation,
      u.CreationDate
    HAVING
      COUNT(DISTINCT p.Id) > 50
  ),
  PostEditDetails AS (
    SELECT
      ph.PostId,
      ph.UserId,
      MAX(ph.CreationDate) AS LastEditDate,
      COUNT(DISTINCT ph.Id) AS EditHistoryCount,
      STRING_AGG(DISTINCT pht.Name, ', ') AS EditedFeatures
    FROM
      PostHistory AS ph
    JOIN
      PostHistoryTypes AS pht
      ON ph.PostHistoryTypeId = pht.Id
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
    GROUP BY
      ph.PostId,
      ph.UserId
  ),
  HighEngagementPosts AS (
    SELECT
      p.Id AS PostId,
      p.Title,
      pt.Name AS PostTypeName,
      u.DisplayName AS OwnerDisplayName,
      p.Score,
      p.ViewCount,
      p.AnswerCount,
      p.CommentCount,
      COALESCE(p.FavoriteCount, 0) AS SafeFavoriteCount,
      CASE
        WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
        ELSE 'Active'
      END AS PostStatus,
      ROW_NUMBER() OVER (
        ORDER BY
          p.Score DESC,
          p.ViewCount DESC
      ) AS PostRank
    FROM
      Posts AS p
    JOIN
      PostTypes AS pt
      ON p.PostTypeId = pt.Id
    LEFT JOIN
      Users AS u
      ON p.OwnerUserId = u.Id
    WHERE
      p.CreationDate >= '2015-01-01'
      AND p.Score > 100
      AND p.ViewCount > 1000
  )
SELECT
  coa.DisplayName AS CollaboratorDisplayName,
  coa.Reputation AS CollaboratorReputation,
  coa.ReputationRank AS CollaboratorRank,
  coa.YearlyReputationRank AS CollaboratorYearlyRank,
  hep.PostId,
  hep.Title,
  hep.PostTypeName,
  hep.OwnerDisplayName AS OriginalPostOwner,
  hep.Score,
  hep.ViewCount,
  hep.AnswerCount,
  hep.SafeFavoriteCount,
  hep.PostStatus,
  ped.LastEditDate,
  ped.EditHistoryCount,
  ped.EditedFeatures,
  CASE
    WHEN SUBSTRING(hep.Title FROM 1 FOR 3) = 'Why' THEN 'Why Question'
    WHEN SUBSTRING(hep.Title FROM 1 FOR 4) = 'What' THEN 'What Question'
    WHEN SUBSTRING(hep.Title FROM 1 FOR 4) = 'How ' THEN 'How Question'
    ELSE 'Other Question Type'
  END AS QuestionCategory
FROM
  RankedUserActivity AS coa
FULL OUTER JOIN
  PostEditDetails AS ped
  ON coa.UserId = ped.UserId
LEFT JOIN
  HighEngagementPosts AS hep
  ON ped.PostId = hep.PostId OR coa.PostCount > 0 AND hep.PostRank <= 5 -- Linking by PostId or if user has high post count and post is highly ranked
WHERE
  coa.Reputation > 10000
  OR hep.PostRank <= 10
UNION ALL
SELECT
  NULL AS CollaboratorDisplayName,
  NULL AS CollaboratorReputation,
  NULL AS CollaboratorRank,
  NULL AS CollaboratorYearlyRank,
  p.Id AS PostId,
  p.Title,
  pt.Name AS PostTypeName,
  u.DisplayName AS OwnerDisplayName,
  p.Score,
  p.ViewCount,
  p.AnswerCount,
  COALESCE(p.FavoriteCount, 0) AS SafeFavoriteCount,
  CASE
    WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
    WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
    ELSE 'Active'
  END AS PostStatus,
  NULL AS LastEditDate,
  NULL AS EditHistoryCount,
  NULL AS EditedFeatures,
  'Uncategorized Post' AS QuestionCategory
FROM
  Posts AS p
JOIN
  PostTypes AS pt
  ON p.PostTypeId = pt.Id
LEFT JOIN
  Users AS u
  ON p.OwnerUserId = u.Id
WHERE
  p.Id NOT IN (SELECT PostId FROM PostEditDetails)
  AND p.Score < 10
ORDER BY
  CollaboratorReputation DESC NULLS LAST,
  Score DESC NULLS LAST;
