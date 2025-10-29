-- {"query": "4588.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1283} 

WITH RankedPosts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Score,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.ViewCount,
    p.CreationDate AS PostCreationDate,
    pt.Name AS PostType,
    ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.FavoriteCount DESC) AS rn_score,
    AVG(CAST(p.Score AS REAL)) OVER (PARTITION BY p.PostTypeId) AS avg_score_per_type,
    COUNT(c.Id) OVER (PARTITION BY p.Id) AS comment_count_for_post,
    LAG(p.Score, 1, 0) OVER (ORDER BY p.CreationDate) AS previous_post_score,
    LEAD(p.Score, 1, 0) OVER (ORDER BY p.CreationDate) AS next_post_score
  FROM Posts AS p
  JOIN PostTypes AS pt
    ON p.PostTypeId = pt.Id
  LEFT JOIN Comments AS c
    ON p.Id = c.PostId
  WHERE
    p.OwnerUserId IS NOT NULL AND p.OwnerUserId <> -1 AND p.ClosedDate IS NULL AND p.CreationDate >= '2023-01-01'
), PostScoreDistribution AS (
  SELECT
    PostId,
    PostType,
    Title,
    Score,
    AnswerCount,
    CommentCount,
    FavoriteCount,
    ViewCount,
    PostCreationDate,
    rn_score,
    avg_score_per_type,
    comment_count_for_post,
    previous_post_score,
    next_post_score,
    CASE
      WHEN Score > avg_score_per_type * 2
      THEN 'HighPerformer'
      WHEN Score < avg_score_per_type / 2
      THEN 'LowPerformer'
      ELSE 'Average'
    END AS performance_tier,
    SUBSTRING(Title, 1, 10) AS first_10_chars_title
  FROM RankedPosts
), UserEngagement AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(p.Id) AS questions_asked,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS answers_given,
    COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS upvotes_received
  FROM Users AS u
  LEFT JOIN Posts AS p
    ON u.Id = p.OwnerUserId
  LEFT JOIN Votes AS v
    ON u.Id = v.UserId AND v.VoteTypeId = 2
  WHERE
    u.CreationDate >= '2023-01-01'
  GROUP BY
    u.Id,
    u.DisplayName,
    u.Reputation
  HAVING
    COUNT(p.Id) > 5 OR SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) > 10
)
SELECT
  psd.PostId,
  psd.PostType,
  psd.Title,
  psd.Score,
  psd.AnswerCount,
  psd.CommentCount,
  psd.FavoriteCount,
  psd.ViewCount,
  psd.PostCreationDate,
  psd.performance_tier,
  psd.first_10_chars_title,
  ue.UserId,
  ue.DisplayName AS EngagingUser,
  ue.Reputation,
  ue.questions_asked,
  ue.answers_given,
  ue.upvotes_received,
  CASE
    WHEN psd.comment_count_for_post > 5 AND psd.Score > 10
    THEN 'Highly Discussed & Rated'
    WHEN psd.rn_score <= 10
    THEN 'Top Ranked by Score/Favorites'
    WHEN psd.Score < 0 AND psd.AnswerCount > 0
    THEN 'Negatively Scored with Answers'
    ELSE 'Standard'
  END AS post_category,
  (
    SELECT
      COUNT(*)
    FROM PostLinks AS pl
    WHERE
      pl.PostId = psd.PostId AND pl.LinkTypeId = 3
  ) AS duplicate_link_count,
  COALESCE(psd.previous_post_score, 0) AS prev_score,
  COALESCE(psd.next_post_score, 0) AS next_score
FROM PostScoreDistribution AS psd
LEFT JOIN UserEngagement AS ue
  ON psd.Score > ue.Reputation / 100
WHERE
  psd.Score > 0 AND psd.PostType IN ('Question', 'Answer')
UNION
SELECT
  NULL,
  'Summary',
  'Average Score Across All Post Types',
  AVG(CAST(Score AS REAL)),
  AVG(CAST(AnswerCount AS REAL)),
  AVG(CAST(CommentCount AS REAL)),
  AVG(CAST(FavoriteCount AS REAL)),
  AVG(CAST(ViewCount AS REAL)),
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL
FROM PostScoreDistribution
WHERE
  PostType IN ('Question', 'Answer');
