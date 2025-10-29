-- {"query": "5347.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 897} 
WITH RankedPosts AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.OwnerUserId,
    p.CreationDate,
    p.Title,
    p.Body,
    p.Tags,
    p.ViewCount,
    p.Score,
    p.CommentCount,
    p.AnswerCount,
    p.LastActivityDate,
    p.FavoriteCount,
    p.LastEditDate,
    p.LastEditorUserId,
    u.Reputation,
    u.DisplayName,
    u.Location,
    u.AccountId,
    ROW_NUMBER() OVER (
      PARTITION BY p.PostTypeId
      ORDER BY
        p.Score DESC NULLS LAST,
        p.ViewCount DESC NULLS LAST,
        p.LastActivityDate DESC
    ) AS rn_by_type
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId IN (1,2) -- Questions and Answers
    AND p.CreationDate >= now() - interval '1 year'
),
Engagement AS (
  SELECT
    rp.PostId,
    rp.PostTypeId,
    rp.OwnerUserId,
    rp.CreationDate,
    rp.Title,
    rp.ViewCount,
    rp.Score,
    rp.LastActivityDate,
    rp.Reputation,
    rp.DisplayName,
    rp.Location,
    rp.AccountId,
    -- Correlated subquery: number of comments per post
    (
      SELECT COUNT(*) FROM Comments c WHERE c.PostId = rp.PostId
    ) AS CommentCount,
    -- Correlated subquery: number of votes of each type for the post
    (
      SELECT COUNT(*) FROM Votes v
      WHERE v.PostId = rp.PostId
        AND v.VoteTypeId IN (2,3) -- UpMod, DownMod
    ) AS UpDownVotes,
    -- Window function example: moving average of score over last 5 posts by same type
    AVG(rp.Score) OVER (
      PARTITION BY rp.PostTypeId
      ORDER BY rp.CreationDate
      ROWS BETWEEN 4 PRECEDING AND CURRENT ROW
    ) AS ScoreMovingAvg
  FROM RankedPosts rp
  WHERE rp.rn_by_type = 1
),
Qualified AS (
  SELECT
    e.*,
    -- Complex predicate and calculation
    CASE
      WHEN e.ViewCount > 1000 AND e.Score > 5 THEN 'Popular_QA'
      WHEN e.ViewCount > 5000 THEN 'Trending'
      ELSE 'Standard'
    END AS Category
  FROM Engagement e
  WHERE e.CommentCount >= 2
     OR e.UpDownVotes >= 5
),
CrossLinks AS (
  SELECT
    q.PostId,
    q.Title,
    q.Category,
    lt.Name AS LinkTypeName,
    pl.RelatedPostId
  FROM Qualified q
  LEFT JOIN PostLinks pl ON pl.PostId = q.PostId
  LEFT JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
),
TagSignal AS (
  SELECT
    cl.PostId,
    cl.Title,
    cl.Category,
    cl.LinkTypeName,
    -- String expression: build a composite tag sentiment from Tags field (split-like)
    (
      SELECT STRING_AGG(t.TagName, ',') FROM (
        SELECT TRIM(x.value::text) AS TagName
        FROM unnest(string_to_array(cl.Title, ' ')) AS x(value)
        WHERE x.value ~ '\\w{4,}'
      ) t
    ) AS TokenTags
  FROM CrossLinks cl
)
SELECT
  ts.PostId,
  ts.Title,
  ts.Category,
  ts.LinkTypeName,
  ts.TokenTags,
  ls.Reputation,
  ls.DisplayName,
  ls.Location,
  ts.creationdate,
  ts.ScoreMovingAvg AS MovingAvgScore,
  ts.ViewCount,
  ts.CommentCount
FROM TagSignal ts
LEFT JOIN Users ls ON EXISTS (
  SELECT 1
  FROM Users u2
  WHERE u2.Id = (
    SELECT OwnerUserId
    FROM Posts p2
    WHERE p2.Id = ts.PostId
  )
) -- intentionally allow any user for demonstration; correlated subquery per post
ORDER BY ts.Category, ts.ScoreMovingAvg DESC
LIMIT 100;