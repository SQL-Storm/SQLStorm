-- {"query": "4303.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1616} 

WITH
  RankedPostHistory AS (
    SELECT
      ph.PostId,
      ph.PostHistoryTypeId,
      ph.CreationDate,
      ph.UserId,
      ph.Comment,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) as rn
    FROM PostHistory AS ph
    WHERE
      ph.PostHistoryTypeId IN (1, 4, 7) -- Title edits/rollbacks
  ),
  PostTitleChanges AS (
    SELECT
      rph.PostId,
      p.Title AS OriginalTitle,
      MAX(CASE WHEN rph.rn = 1 THEN ph_latest.Comment ELSE NULL END) AS LatestTitleChangeComment,
      MAX(CASE WHEN rph.rn = 1 THEN rph.CreationDate ELSE NULL END) AS LatestTitleChangeDate,
      COUNT(DISTINCT CASE WHEN rph.PostHistoryTypeId = 1 THEN 1 ELSE NULL END) AS InitialTitleCount,
      COUNT(DISTINCT CASE WHEN rph.PostHistoryTypeId = 4 THEN 1 ELSE NULL END) AS EditTitleCount,
      COUNT(DISTINCT CASE WHEN rph.PostHistoryTypeId = 7 THEN 1 ELSE NULL END) AS RollbackTitleCount,
      SUM(CASE WHEN rph.PostHistoryTypeId IN (1, 4, 7) THEN 1 ELSE 0 END) AS TotalTitleHistoryEntries
    FROM Posts AS p
    LEFT JOIN RankedPostHistory AS rph
      ON p.Id = rph.PostId
    LEFT JOIN PostHistory AS ph_latest
      ON rph.PostId = ph_latest.PostId
      AND rph.rn = 1
    GROUP BY
      rph.PostId,
      p.Title
  ),
  UserReputation AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      COUNT(DISTINCT b.Id) AS BadgeCount,
      SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
      SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
      SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Users AS u
    LEFT JOIN Badges AS b
      ON u.Id = b.UserId
    GROUP BY
      u.Id,
      u.DisplayName,
      u.Reputation
  ),
  PostAggregates AS (
    SELECT
      p.Id AS PostId,
      p.PostTypeId,
      pt.Name AS PostTypeName,
      p.OwnerUserId,
      p.CreationDate,
      p.Score,
      p.ViewCount,
      p.AnswerCount,
      p.CommentCount,
      p.FavoriteCount,
      p.ClosedDate,
      CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS IsClosed,
      (
        SELECT
          COUNT(*)
        FROM Comments AS c
        WHERE
          c.PostId = p.Id AND c.Score < 0
      ) AS NegativeScoreComments,
      (
        SELECT
          SUM(v.BountyAmount)
        FROM Votes AS v
        WHERE
          v.PostId = p.Id AND v.VoteTypeId = 8
      ) AS TotalBountyAmount,
      SUBSTRING(p.Tags, 2, CHARINDEX('>', p.Tags) - 2) AS FirstTag,
      REPLACE(p.Tags, '><', ' ') AS TagsWithSpaces
    FROM Posts AS p
    JOIN PostTypes AS pt
      ON p.PostTypeId = pt.Id
    WHERE
      p.PostTypeId IN (1, 2) -- Questions and Answers
  )
SELECT
  pa.PostId,
  pa.PostTypeName,
  pa.CreationDate,
  pa.Score,
  pa.ViewCount,
  pa.AnswerCount,
  pa.CommentCount,
  pa.FavoriteCount,
  pa.IsClosed,
  pa.NegativeScoreComments,
  pa.TotalBountyAmount,
  pa.FirstTag,
  pa.TagsWithSpaces,
  COALESCE(ptc.OriginalTitle, 'N/A') AS EffectiveTitle,
  COALESCE(ptc.LatestTitleChangeComment, 'No Title Changes') AS LastTitleModification,
  COALESCE(ur.DisplayName, 'Community') AS OwnerDisplayName,
  ur.Reputation AS OwnerReputation,
  ur.BadgeCount AS OwnerBadgeCount,
  ur.GoldBadges AS OwnerGoldBadges,
  ur.SilverBadges AS OwnerSilverBadges,
  ur.BronzeBadges AS OwnerBronzeBadges,
  (
    CASE
      WHEN ur.Reputation > 100000
      THEN 'Legendary'
      WHEN ur.Reputation > 50000
      THEN 'Expert'
      WHEN ur.Reputation > 10000
      THEN 'Experienced'
      WHEN ur.Reputation > 1000
      THEN 'Proficient'
      ELSE 'Novice'
    END
  ) AS ReputationLevel,
  CASE
    WHEN pa.ClosedDate IS NOT NULL AND pa.CreationDate < DATEADD(day, -30, pa.ClosedDate)
    THEN 'Old Closed Post'
    WHEN pa.Score > 50 AND pa.ViewCount > 10000
    THEN 'Popular High-Score Post'
    WHEN pa.FavoriteCount > 10
    THEN 'Highly Favorited'
    WHEN pa.AnswerCount > 15
    THEN 'Prolific Question'
    WHEN pa.NegativeScoreComments > 5
    THEN 'Contentious Post'
    WHEN pa.TotalBountyAmount > 0
    THEN 'Bountied Post'
    ELSE 'Standard Post'
  END AS PostCategorization,
  (
    SELECT
      COUNT(pl.Id)
    FROM PostLinks AS pl
    WHERE
      pl.PostId = pa.PostId AND pl.LinkTypeId = 3
  ) AS DuplicateLinks,
  CASE
    WHEN ptc.TotalTitleHistoryEntries > 0 AND ptc.InitialTitleCount = 0 THEN 'Title Modified/Rolled Back'
    WHEN ptc.TotalTitleHistoryEntries > 0 AND ptc.InitialTitleCount > 0 THEN 'Initial Title Recorded'
    ELSE 'No Title History'
  END AS TitleHistoryStatus
FROM PostAggregates AS pa
LEFT JOIN PostTitleChanges AS ptc
  ON pa.PostId = ptc.PostId
LEFT JOIN UserReputation AS ur
  ON pa.OwnerUserId = ur.UserId
WHERE
  pa.Score > 0
  OR pa.CommentCount > 0
  OR pa.FavoriteCount > 0
  OR pa.IsClosed = 1
ORDER BY
  pa.CreationDate DESC,
  pa.Score DESC
LIMIT 1000;
