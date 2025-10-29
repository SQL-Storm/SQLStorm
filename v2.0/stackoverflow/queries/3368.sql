WITH
UserRanks AS (
  SELECT u.Id,
         u.DisplayName,
         u.Reputation,
         COALESCE(u.Location,'[unknown]') AS Location,
         ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS rn,
         (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
         (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS SilverBadges
  FROM Users u
  WHERE u.Reputation > 5000
),
-- Expand tags by splitting the Tags string using a generic string-splitting method (UNNEST of STRING_SPLIT-like results).
RecentActivity AS (
  SELECT p.Id,
         p.OwnerUserId,
         p.PostTypeId,
         p.CreationDate,
         p.Score,
         p.ViewCount,
         TRIM(tag) AS Tag,
         ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn_owner
  FROM Posts p
  LEFT JOIN (
    -- Produce rows by splitting the Tags string on '><'. This implementation uses a recursive CTE to emulate regexp_split_to_table.
    WITH RECURSIVE split(tag, rest) AS (
      SELECT
        '' AS tag,
        COALESCE(p.Tags,'') AS rest
      UNION ALL
      SELECT
        CASE
          WHEN POSITION('><' IN rest) = 0 THEN rest
          ELSE SUBSTR(rest, 1, POSITION('><' IN rest)-1)
        END,
        CASE
          WHEN POSITION('><' IN rest) = 0 THEN ''
          ELSE SUBSTR(rest, POSITION('><' IN rest)+2)
        END
      FROM split
      WHERE rest <> ''
    )
    SELECT tag FROM split WHERE TRIM(tag) <> ''
  ) AS split_tags ON TRUE
  WHERE p.CreationDate >= (CAST('2024-10-01' AS date) - INTERVAL '180 days')
),
TagAggregates AS (
  SELECT t.TagName,
         COUNT(CASE WHEN ra.PostTypeId = 1 THEN 1 END) AS QCount,
         COUNT(CASE WHEN ra.PostTypeId = 2 THEN 1 END) AS ACount,
         AVG(ra.Score) AS AvgScore,
         SUM(COALESCE(ra.ViewCount,0)) AS TotalViews
  FROM Tags t
  LEFT JOIN RecentActivity ra ON ra.Tag = t.TagName
  GROUP BY t.TagName
),
UserPostStats AS (
  SELECT ur.Id,
         COUNT(ra.Id) AS PostTotal,
         SUM(CASE WHEN ra.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionTotal,
         SUM(CASE WHEN ra.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerTotal,
         MAX(ra.CreationDate) AS LastPostDate,
         MAX(CASE WHEN ra.PostTypeId = 1 THEN ra.Score END) AS MaxQScore,
         MAX(CASE WHEN ra.PostTypeId = 2 THEN ra.Score END) AS MaxAScore
  FROM UserRanks ur
  LEFT JOIN RecentActivity ra ON ra.OwnerUserId = ur.Id
  WHERE ur.rn <= 100
  GROUP BY ur.Id
),
LatestVoteCheck AS (
  SELECT ur.Id,
         EXISTS (
           SELECT 1
           FROM Votes v
           JOIN Posts p ON p.Id = v.PostId
           WHERE p.OwnerUserId = ur.Id
             AND p.CreationDate = (
               SELECT MAX(p2.CreationDate)
               FROM Posts p2
               WHERE p2.OwnerUserId = ur.Id
             )
             AND v.VoteTypeId = 2
         ) AS LatestPostHasUpvote
  FROM UserRanks ur
),
TopTag AS (
  SELECT t.TagName
  FROM Tags t
  ORDER BY t.Count DESC
  LIMIT 1
)
SELECT ur.Id,
       ur.DisplayName,
       ur.Reputation,
       ur.Location,
       ur.GoldBadges,
       ur.SilverBadges,
       ups.PostTotal,
       ups.QuestionTotal,
       ups.AnswerTotal,
       ups.LastPostDate,
       ups.MaxQScore,
       ups.MaxAScore,
       COALESCE(ta.AvgScore,0) AS AvgTagScore,
       COALESCE(ta.TotalViews,0) AS TagViews,
       CASE WHEN ups.QuestionTotal = 0 THEN NULL
            ELSE ROUND(CAST(ups.AnswerTotal AS numeric)/ups.QuestionTotal,2)
       END AS AnswerRatio,
       lvc.LatestPostHasUpvote
FROM UserRanks ur
LEFT JOIN UserPostStats ups ON ups.Id = ur.Id
LEFT JOIN TopTag tt ON TRUE
LEFT JOIN TagAggregates ta ON ta.TagName = tt.TagName
LEFT JOIN LatestVoteCheck lvc ON lvc.Id = ur.Id
WHERE (ur.GoldBadges + ur.SilverBadges) >= 3
ORDER BY ur.Reputation DESC
LIMIT 20;