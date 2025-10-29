-- {"query": "5546.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 999} 
WITH recent_questions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.OwnerUserId,
    p.ViewCount,
    p.Score,
    p.Tags,
    p.CommentCount,
    p.LastActivityDate,
    p.AcceptedAnswerId,
    p.ParentId,
    p.PostTypeId,
    p.LastEditDate,
    p.Body,
    p.FavoriteCount
  FROM Posts p
  WHERE p.PostTypeId = 1 -- Questions
    AND p.CreationDate >= NOW() - INTERVAL '30 days'
),
tag_popularity AS (
  SELECT
    unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName,
    p.Id AS PostId
  FROM Posts p
  WHERE p.PostTypeId = 1
),
tag_metrics AS (
  SELECT
    t.TagName,
    COUNT(*) AS QuestionCount,
    AVG(p.ViewCount) AS AvgViews,
    AVG(p.Score) AS AvgScore,
    MAX(p.CreationDate) AS LastQuestionDate
  FROM tag_popularity t
  JOIN Posts p ON p.Id = t.PostId
  GROUP BY t.TagName
),
top_tags AS (
  SELECT
    TagName,
    QuestionCount,
    AvgViews,
    AvgScore,
    LastQuestionDate,
    ROW_NUMBER() OVER (ORDER BY QuestionCount DESC, AvgViews DESC, AvgScore DESC) AS rn
  FROM tag_metrics
  WHERE QuestionCount > 0
)
SELECT
  rq.PostId AS question_id,
  rq.Title AS question_title,
  rq.CreationDate AS question_creation,
  rq.OwnerUserId AS owner_id,
  ru.DisplayName AS owner_display_name,
  rq.ViewCount,
  rq.Score,
  rq.Tags,
  rq.LastActivityDate,
  rq.LastEditDate,
  ARRAY_AGG(DISTINCT cl.Name) FILTER (WHERE cr.Name IS NULL) AS close_reasons_possible,
  vt.Name AS latest_vote_type,
  v2.BountyAmount AS latest_bounty,
  tt.TagName AS associated_tag,
  tm.QuestionCount AS tag_question_count,
  tm.AvgViews AS tag_avg_views,
  tm.AvgScore AS tag_avg_score,
  (SELECT COUNT(*) FROM Comments c WHERE c.PostId = rq.PostId) AS comment_count,
  (SELECT STRING_AGG(CONCAT('User:', u.DisplayName, ' (', u.Id, ')', ' Score=', COALESCE(vt2.BountyAmount,0)), '; ') 
     FROM Votes vt_user
     JOIN Users u ON u.Id = vt_user.UserId
     LEFT JOIN Votes vt2 ON vt2.PostId = rq.PostId AND vt2.UserId = u.Id
     WHERE vt_user.PostId = rq.PostId) AS user_vote_briefs
FROM recent_questions rq
LEFT JOIN Users ru ON rq.OwnerUserId = ru.Id
LEFT JOIN Votes v ON v.PostId = rq.PostId
LEFT JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
LEFT JOIN (SELECT PostId, MAX(Case WHEN VoteTypeId = 9 THEN CreationDate END) AS LatestBountyDate, MAX(BountyAmount) AS BountyAmount
           FROM Votes
           WHERE VoteTypeId = 8 OR VoteTypeId = 9
           GROUP BY PostId) v2 ON v2.PostId = rq.PostId
LEFT JOIN Tags tt ON tt.Id = (SELECT i FROM unnest(string_to_array(substring(rq.Tags, 2, length(rq.Tags)-2), '><')) AS i LIMIT 1)
LEFT JOIN (SELECT PostId, STRING_AGG(Name, ',') AS CloseReasons
           FROM PostHistory ph
           JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
           WHERE ph.PostId IS NOT NULL
             AND ph.PostHistoryTypeId = 10
           GROUP BY PostId) phc ON phc.PostId = rq.PostId
LEFT JOIN CloseReasonTypes cr ON phc.CloseReasons IS NOT NULL
LEFT JOIN PostLinks pl ON pl.PostId = rq.PostId
LEFT JOIN (SELECT PostId, MAX(Score) AS max_score FROM Posts GROUP BY PostId) pmax ON pmax.PostId = rq.PostId
LEFT JOIN top_tags tm ON tm.TagName = tt.TagName
GROUP BY
  rq.PostId, rq.Title, rq.CreationDate, rq.OwnerUserId, ru.DisplayName,
  rq.ViewCount, rq.Score, rq.Tags, rq.LastActivityDate, rq.LastEditDate,
  vt.Name, v2.BountyAmount, tt.TagName, tm.QuestionCount, tm.AvgViews, tm.AvgScore;