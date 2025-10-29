-- {"query": "4585.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1202} 

WITH
  RankedPostHistory AS (
    SELECT
      ph.PostId,
      ph.PostHistoryTypeId,
      ph.UserId,
      ph.CreationDate,
      ph.Text,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) as rn
    FROM PostHistory AS ph
    WHERE
      ph.PostHistoryTypeId IN (
        1,
        2,
        3,
        4,
        5,
        6,
        7,
        8,
        9,
        10,
        11,
        12,
        13,
        14,
        15,
        16,
        17,
        18,
        19,
        20,
        22,
        24,
        25,
        31,
        33,
        34,
        35,
        36,
        37,
        38,
        50,
        52,
        53,
        66
      )
  ),
  LatestPostActivity AS (
    SELECT
      p.Id AS PostId,
      p.Title,
      p.OwnerUserId,
      p.CreationDate AS PostCreationDate,
      p.LastActivityDate,
      u.DisplayName AS OwnerDisplayName,
      SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
      SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
      COUNT(DISTINCT c.Id) AS CommentCount,
      MAX(ph.CreationDate) AS LastEditDate,
      MAX(CASE WHEN ph.PostHistoryTypeId IN (10, 11) THEN ph.CreationDate ELSE NULL END) AS LastCloseOrOpenDate,
      COUNT(DISTINCT pl.Id) AS LinkCount
    FROM Posts AS p
    LEFT JOIN Users AS u
      ON p.OwnerUserId = u.Id
    LEFT JOIN Votes AS v
      ON p.Id = v.PostId
    LEFT JOIN Comments AS c
      ON p.Id = c.PostId
    LEFT JOIN RankedPostHistory AS ph
      ON p.Id = ph.PostId AND ph.rn = 1
    LEFT JOIN PostLinks AS pl
      ON p.Id = pl.PostId OR p.Id = pl.RelatedPostId
    GROUP BY
      p.Id,
      p.Title,
      p.OwnerUserId,
      p.CreationDate,
      p.LastActivityDate,
      u.DisplayName
  )
SELECT
  lpa.PostId,
  lpa.Title,
  lpa.OwnerDisplayName,
  lpa.PostCreationDate,
  lpa.LastActivityDate,
  lpa.UpVoteCount,
  lpa.DownVoteCount,
  lpa.CommentCount,
  lpa.LinkCount,
  lpa.LastEditDate,
  lpa.LastCloseOrOpenDate,
  COALESCE(ph_last.Text, 'No Revision Comment') AS LastRevisionComment,
  CASE
    WHEN lpa.UpVoteCount > lpa.DownVoteCount * 2 THEN 'Highly Voted Up'
    WHEN lpa.DownVoteCount > lpa.UpVoteCount * 2 THEN 'Highly Voted Down'
    WHEN lpa.CommentCount > 10 THEN 'Chatty Post'
    WHEN lpa.LinkCount > 5 THEN 'Well Linked'
    WHEN lpa.LastEditDate IS NOT NULL AND lpa.LastEditDate > lpa.PostCreationDate + INTERVAL '7 day' THEN 'Recently Edited'
    WHEN lpa.LastCloseOrOpenDate IS NOT NULL THEN 'Closed or Reopened'
    ELSE 'Standard Activity'
  END AS ActivityCategory,
  CASE
    WHEN lpa.Title IS NULL OR LENGTH(TRIM(lpa.Title)) = 0 THEN 'Missing Title'
    WHEN LENGTH(lpa.Title) > 100 THEN 'Long Title'
    ELSE 'Standard Title'
  END AS TitleQuality,
  (
    SELECT
      COUNT(*)
    FROM Badges AS b
    WHERE
      b.UserId = lpa.OwnerUserId
      AND b.Class IN (1, 2) /* Gold or Silver badges */
  ) AS OwnerHighValueBadges,
  (
    SELECT
      COUNT(*)
    FROM Votes AS v_sub
    WHERE
      v_sub.UserId = lpa.OwnerUserId
      AND v_sub.VoteTypeId = 8 /* BountyStart */
  ) AS OwnerBountyStarts
FROM LatestPostActivity AS lpa
LEFT JOIN RankedPostHistory AS ph_last
  ON lpa.PostId = ph_last.PostId AND ph_last.rn = 1
WHERE
  lpa.PostCreationDate > '2023-01-01'
  AND (
    lpa.UpVoteCount + lpa.DownVoteCount + lpa.CommentCount > 0
    OR lpa.LinkCount > 0
  )
ORDER BY
  lpa.LastActivityDate DESC
LIMIT 1000;
