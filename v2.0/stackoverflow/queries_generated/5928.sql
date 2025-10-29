-- {"query": "5928.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1047} 
WITH RecentUserActivity AS (
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
    u.ProfileImageUrl,
    u.EmailHash,
    u.AccountId,
    ROW_NUMBER() OVER (ORDER BY u.LastAccessDate DESC) AS rn
  FROM Users u
),
PostEngagement AS (
  SELECT
    p.Id AS PostId,
    p.OwnerUserId,
    p.PostTypeId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.Body,
    COALESCE(vs.SumUp, 0) AS UpVotesSum,
    COALESCE(vs.SumDown, 0) AS DownVotesSum,
    COALESCE(p.ParentId, 0) AS ParentId
  FROM Posts p
  LEFT JOIN (
    SELECT
      PostId,
      SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS SumUp,
      SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS SumDown
    FROM Votes
    GROUP BY PostId
  ) vs ON vs.PostId = p.Id
),
ComplexFilters AS (
  SELECT
    pe.PostId,
    pe.OwnerUserId,
    pe.PostTypeId,
    pe.Title,
    pe.Tags,
    pe.CreationDate,
    pe.LastActivityDate,
    pe.Score,
    pe.ViewCount,
    pe.AnswerCount,
    pe.CommentCount,
    pe.FavoriteCount,
    pe.Body,
    pe.UpVotesSum,
    pe.DownVotesSum,
    pe.ParentId,
    u.Reputation,
    u.AccountId,
    u.Location,
    u.LastAccessDate
  FROM PostEngagement pe
  LEFT JOIN Users u ON pe.OwnerUserId = u.Id
  WHERE
    pe.PostTypeId IN (1,2) -- Questions and Answers
    AND pe.Score > 0
    AND pe.ViewCount > 0
    AND (DATE(pe.CreationDate) >= CURRENT_DATE - INTERVAL '180 days')
    AND (pe.LastActivityDate IS NOT NULL)
),
RankedPosts AS (
  SELECT
    cf.*,
    ROW_NUMBER() OVER (
      PARTITION BY cf.PostTypeId
      ORDER BY
        cf.Score * 2 + cf.ViewCount + cf.UpVotesSum - cf.DownVotesSum
        DESC
  ) AS rk
  FROM ComplexFilters cf
),
Aggregated AS (
  SELECT
    rp.PostId,
    rp.Title,
    rp.Tags,
    rp.PostTypeId,
    rp.CreationDate,
    rp.LastActivityDate,
    rp.Score,
    rp.ViewCount,
    rp.AnswerCount,
    rp.CommentCount,
    rp.FavoriteCount,
    rp.Body,
    rp.UpVotesSum,
    rp.DownVotesSum,
    rp.ParentId,
    rp.Reputation,
    rp.Location,
    rp.AccountId,
    rp.LastAccessDate,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = rp.PostId AND pl.LinkTypeId = 1) AS LinkedCount,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = rp.PostId AND pl.LinkTypeId = 3) AS DuplicateCount,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = rp.PostId AND v.VoteTypeId = 10) AS DeletionVotes
  FROM RankedPosts rp
  WHERE rp.rk = 1
),
FinalOutput AS (
  SELECT
    a.PostId,
    a.Title,
    a.Tags,
    CASE a.PostTypeId
      WHEN 1 THEN 'Question'
      WHEN 2 THEN 'Answer'
      ELSE 'Other'
    END AS PostType,
    a.CreationDate,
    a.LastActivityDate,
    a.Score,
    a.ViewCount,
    a.AnswerCount,
    a.CommentCount,
    a.FavoriteCount,
    a.Body,
    a.UpVotesSum,
    a.DownVotesSum,
    a.ParentId,
    a.Reputation,
    a.Location,
    a.AccountId,
    a.LastAccessDate,
    a.LinkedCount,
    a.DuplicateCount,
    a.DeletionVotes,
    -- Complex computed expression as a light-weight performance stress test
    (a.Score * CAST((CASE WHEN a.ViewCount > 0 THEN a.ViewCount ELSE 1 END) AS DECIMAL(18,4)))
      / NULLIF((1.0 + ABS(COALESCE(a.Reputation,0))), 0.001) AS ScoreDensity
  FROM Aggregated a
)
SELECT *
FROM FinalOutput
ORDER BY PostType, LastActivityDate DESC
LIMIT 100;