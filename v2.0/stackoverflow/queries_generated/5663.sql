-- {"query": "5663.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 992} 
WITH RankedPosts AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.OwnerUserId,
    p.Score,
    p.ViewCount,
    p.LastActivityDate,
    p.ParentId,
    p.AcceptedAnswerId,
    p.CommentCount,
    p.FavoriteCount,
    p.ContentLicense,
    p.LastEditorUserId,
    u.Reputation,
    u.DisplayName AS OwnerDisplayName,
    u.Location,
    u.AccountId,
    CASE
      WHEN p.PostTypeId = 1 THEN 1
      ELSE 0
    END AS IsQuestion,
    COALESCE(a.Score, 0) AS AcceptedAnswerScore,
    ROW_NUMBER() OVER (
      PARTITION BY CASE WHEN p.PostTypeId = 1 THEN p.OwnerUserId ELSE NULL END
      ORDER BY p.CreationDate DESC
    ) AS rn_owner
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN Posts a ON p.AcceptedAnswerId = a.Id
  LEFT JOIN PostLinks pl ON p.Id = pl.PostId
  LEFT JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
  WHERE p.CreationDate >= NOW() - INTERVAL '2 years'
),
DistinctQuestions AS (
  SELECT
    rp.PostId,
    rp.Title,
    rp.Tags,
    rp.CreationDate,
    rp.OwnerUserId,
    rp.Reputation,
    rp.OwnerDisplayName,
    rp.ViewCount,
    rp.Score,
    rp.CommentCount,
    rp.AcceptedAnswerId,
    rp.AcceptedAnswerScore,
    rp.IsQuestion,
    ROW_NUMBER() OVER (ORDER BY rp.Reputation DESC, rp.ViewCount DESC, rp.CreationDate DESC) AS rn
  FROM RankedPosts rp
  WHERE rp.IsQuestion = 1
),
Composite AS (
  SELECT
    dq.PostId,
    dq.Title,
    string_agg(t.TagName, ',') FILTER (WHERE t.TagName IS NOT NULL) AS TopTags,
    dq.CreationDate,
    dq.OwnerDisplayName,
    dq.Reputation,
    dq.ViewCount,
    dq.Score,
    dq.CommentCount,
    coa.Id AS ClosestActivityVersion,
    coa.CreationDate AS ActivityDate,
    COALESCE(v.SumBounties, 0) AS SumBounties
  FROM DistinctQuestions dq
  LEFT JOIN LATERAL (
    SELECT
      ta.TagName
    FROM unnest(string_to_array(dq.Tags, '>')) AS tname
    LEFT JOIN Tags t ON trim(tname) = trim(t.TagName)
    WHERE t.Count > 0
  ) t ON true
  LEFT JOIN (
    SELECT
      p.OwnerUserId,
      MAX(p.LastActivityDate) AS LastActivity
    FROM Posts p
    GROUP BY p.OwnerUserId
  ) coa ON coa.LastActivity = dq.CreationDate
  LEFT JOIN (
    SELECT PostId, SUM(BountyAmount) AS SumBounties
    FROM Votes v
    WHERE v.VoteTypeId = 8 OR v.VoteTypeId = 9
    GROUP BY PostId
  ) v ON v.PostId = dq.PostId
  GROUP BY dq.PostId, dq.Title, dq.CreationDate, dq.OwnerDisplayName, dq.Reputation, dq.ViewCount, dq.Score, dq.CommentCount, coa.Id, coa.CreationDate, SumBounties
)
SELECT
  c.PostId,
  c.Title,
  c.TopTags,
  c.CreationDate,
  c.OwnerDisplayName,
  c.Reputation,
  c.ViewCount,
  c.Score,
  c.CommentCount,
  c.ActivityDate,
  c.SumBounties,
  COALESCE(b.Score, 0) AS LastCommentScore,
  b.Text AS LastCommentText
FROM Composite c
LEFT JOIN (
  SELECT
    co.PostId,
    co.Score,
    co.Text,
    ROW_NUMBER() OVER (PARTITION BY co.PostId ORDER BY co.CreationDate DESC) AS rn
  FROM Comments co
) b ON b.PostId = c.PostId AND b.rn = 1
LEFT JOIN (
  SELECT
    p.ParentId,
    AVG(p.Score) AS AvgChildScore
  FROM Posts p
  WHERE p.ParentId IS NOT NULL
  GROUP BY p.ParentId
) ch ON ch.ParentId = c.PostId
WHERE c.SumBounties > 0 OR c.ViewCount > 1000
ORDER BY c.Reputation DESC, c.ViewCount DESC
LIMIT 100;