-- {"query": "313.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 16245} 
WITH
tag_exploded AS (
  SELECT p.Id AS PostId,
         te.Tag
  FROM Posts p
  CROSS JOIN LATERAL unnest(
    string_to_array(
      substring(p.Tags, 2, GREATEST(0, length(p.Tags) - 2)),
      '><'
    )
  ) AS te(Tag)
  WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL AND p.Tags <> ''
),
user_post_aggs AS (
  SELECT u.Id AS UserId,
         u.DisplayName,
         COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionsPosted,
         COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswersPosted,
         SUM(p.Score) FILTER (WHERE p.PostTypeId = 1) AS QScoreSum,
         SUM(p.Score) FILTER (WHERE p.PostTypeId = 2) AS AScoreSum,
         AVG(p.Score) FILTER (WHERE p.PostTypeId = 2) AS AScoreAvg,
         SUM(CASE WHEN q.AcceptedAnswerId = p.Id THEN 1 ELSE 0 END) AS TimesAccepted,
         MAX(p.CreationDate) AS LastPostDate
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Posts q ON q.AcceptedAnswerId = p.Id
  GROUP BY u.Id, u.DisplayName
),
badge_summary AS (
  SELECT b.UserId,
         COUNT(*) AS TotalBadges,
         SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS Gold,
         SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS Silver,
         SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS Bronze,
         SUM(CASE WHEN b.TagBased = 1 THEN 1 ELSE 0 END) AS TagBadges
  FROM Badges b
  GROUP BY b.UserId
),
latest_comments AS (
  SELECT c.*,
         ROW_NUMBER() OVER (PARTITION BY c.PostId ORDER BY c.CreationDate DESC) AS rn
  FROM Comments c
),
post_latest_comment AS (
  SELECT lc.PostId, lc.Id AS CommentId, lc.Text AS CommentText, lc.CreationDate AS CommentDate, lc.UserId AS CommentUserId
  FROM latest_comments lc
  WHERE lc.rn = 1
),
duplicate_roots AS (
  SELECT pl.PostId AS StartPostId,
         pl.RelatedPostId AS RootPostId,
         ARRAY[pl.PostId::text, pl.RelatedPostId::text] AS path,
         1 AS depth
  FROM PostLinks pl
  WHERE pl.LinkTypeId = 3
  UNION ALL
  SELECT dr.StartPostId,
         pl.RelatedPostId,
         array_cat(dr.path, ARRAY[pl.RelatedPostId::text]),
         dr.depth + 1
  FROM duplicate_roots dr
  JOIN PostLinks pl ON pl.PostId = dr.RootPostId AND pl.LinkTypeId = 3
  WHERE NOT (pl.RelatedPostId::text = ANY(dr.path))
),
canonical_duplicate AS (
  SELECT StartPostId,
         RootPostId,
         depth,
         ROW_NUMBER() OVER (PARTITION BY StartPostId ORDER BY depth DESC) AS rn
  FROM duplicate_roots
),
final_duplicate_root AS (
  SELECT cd.StartPostId AS PostId, cd.RootPostId AS CanonicalRootId
  FROM canonical_duplicate cd
  WHERE cd.rn = 1
),
answer_metrics AS (
  SELECT a.Id AS AnswerId,
         a.ParentId AS QuestionId,
         a.OwnerUserId,
         a.CreationDate AS AnswerDate,
         q.CreationDate AS QuestionDate,
         EXTRACT(EPOCH FROM (a.CreationDate - q.CreationDate)) AS ResponseSeconds,
         a.Score AS AnswerScore,
         ROW_NUMBER() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC) AS AnswerRankByScore,
         RANK() OVER (PARTITION BY a.ParentId ORDER BY a.CreationDate ASC) AS AnswerRankByTime
  FROM Posts a
  LEFT JOIN Posts q ON q.Id = a.ParentId
  WHERE a.PostTypeId = 2
),
user_answer_stats AS (
  SELECT am.OwnerUserId AS UserId,
         COUNT(*) AS Answers,
         SUM(am.AnswerScore) AS TotalAnswerScore,
         AVG(am.AnswerScore) AS AvgAnswerScore,
         AVG(am.ResponseSeconds) FILTER (WHERE am.ResponseSeconds IS NOT NULL) AS AvgResponseSeconds,
         SUM(CASE WHEN EXISTS (SELECT 1 FROM Posts q WHERE q.Id = am.QuestionId AND q.AcceptedAnswerId = am.AnswerId) THEN 1 ELSE 0 END) AS AcceptedCount
  FROM answer_metrics am
  GROUP BY am.OwnerUserId
),
tag_popularity AS (
  SELECT te.Tag,
         COUNT(*) AS QuestionCount,
         AVG(p.Score) AS AvgQuestionScore,
         AVG(p.AnswerCount) AS AvgAnswerCount,
         SUM(p.ViewCount) AS TotalViews,
         COUNT(DISTINCT p.OwnerUserId) AS DistinctAskers,
         MAX(p.Score) AS MaxQuestionScore
  FROM tag_exploded te
  JOIN Posts p ON p.Id = te.PostId
  GROUP BY te.Tag
),
tag_user_scores AS (
  SELECT te.Tag,
         COALESCE(p.OwnerUserId, -1) AS UserId,
         COALESCE(u.DisplayName, 'unknown') AS DisplayName,
         SUM(COALESCE(p.Score,0)) AS ScoreSum,
         COUNT(*) AS PostsInTag
  FROM tag_exploded te
  LEFT JOIN Posts p ON p.Id = te.PostId
  LEFT JOIN Users u ON u.Id = p.OwnerUserId
  GROUP BY te.Tag, p.OwnerUserId, u.DisplayName
),
tag_user_scores_with_rn AS (
  SELECT tus.*,
         ROW_NUMBER() OVER (PARTITION BY tus.Tag ORDER BY tus.ScoreSum DESC NULLS LAST) AS rn
  FROM tag_user_scores tus
),
top_tag_contributors AS (
  SELECT Tag, UserId, DisplayName, ScoreSum, PostsInTag
  FROM tag_user_scores_with_rn
  WHERE rn <= 3
),
top_by_questions AS (
  SELECT Tag, QuestionCount AS MetricValue, 'questions' AS Metric
  FROM tag_popularity
  ORDER BY QuestionCount DESC
  LIMIT 10
),
top_by_views AS (
  SELECT Tag, TotalViews AS MetricValue, 'views' AS Metric
  FROM tag_popularity
  ORDER BY TotalViews DESC
  LIMIT 10
),
top_tags_combined AS (
  SELECT * FROM top_by_questions
  UNION
  SELECT * FROM top_by_views
),
intersect_top_qv AS (
  SELECT Tag FROM top_by_questions
  INTERSECT
  SELECT Tag FROM top_by_views
),
top_questions_not_views AS (
  SELECT Tag FROM top_by_questions
  EXCEPT
  SELECT Tag FROM top_by_views
),
user_reputation_rank AS (
  SELECT u.Id AS UserId,
         u.DisplayName,
         COALESCE(u.Reputation,0) AS Reputation,
         NTILE(100) OVER (ORDER BY COALESCE(u.Reputation,0) DESC) AS ReputationPercRank,
         ROW_NUMBER() OVER (ORDER BY COALESCE(u.Reputation,0) DESC) AS ReputationRank
  FROM Users u
),
final_scores AS (
  SELECT u.Id AS UserId,
         COALESCE(u.DisplayName,'<deleted>') AS DisplayName,
         COALESCE(upa.QuestionsPosted,0) AS QuestionsPosted,
         COALESCE(upa.AnswersPosted,0) AS AnswersPosted,
         COALESCE(usa.Answers,0) AS Answers,
         COALESCE(usa.TotalAnswerScore,0) AS TotalAnswerScore,
         COALESCE(usa.AvgAnswerScore,0) AS AvgAnswerScore,
         COALESCE(bad.TotalBadges,0) AS TotalBadges,
         COALESCE(bad.Gold,0) AS GoldBadges,
         COALESCE(bad.Silver,0) AS SilverBadges,
         COALESCE(bad.Bronze,0) AS BronzeBadges,
         COALESCE(ur.Reputation,0) AS Reputation,
         ur.ReputationRank,
         ur.ReputationPercRank,
         CASE WHEN COALESCE(usa.Answers,0) = 0 THEN NULL ELSE ROUND((COALESCE(usa.AcceptedCount,0)::numeric / NULLIF(usa.Answers,0)) * 100, 2) END AS AcceptanceRatePercent,
         COALESCE(usa.AvgResponseSeconds,0) AS AvgResponseSeconds,
         (COALESCE(usa.TotalAnswerScore,0)::numeric) / NULLIF(LOG(GREATEST(2, COALESCE(ur.Reputation,1))) + 1, 0)
           + (COALESCE(bad.Gold,0) * 5 + COALESCE(bad.Silver,0) * 2 + COALESCE(bad.Bronze,0) * 1) * 0.5
           AS InfluenceScore,
         ('User: ' || COALESCE(u.DisplayName,'<deleted>') || E'\nRep:' || COALESCE(ur.Reputation::text,'0') || E'\nBadges:' || COALESCE(bad.TotalBadges::text,'0')) AS TextSummary
  FROM Users u
  LEFT JOIN user_post_aggs upa ON upa.UserId = u.Id
  LEFT JOIN user_answer_stats usa ON usa.UserId = u.Id
  LEFT JOIN badge_summary bad ON bad.UserId = u.Id
  LEFT JOIN user_reputation_rank ur ON ur.UserId = u.Id
),
flagged_posts AS (
  SELECT p.Id AS PostId, p.Title, p.PostTypeId, p.ViewCount, p.Score,
         COALESCE(p.AnswerCount,0) AS AnswerCount,
         COALESCE(p.CommentCount,0) AS CommentCount,
         MAX(ph.CreationDate) AS LastHistoryDate,
         (SELECT pt.Name FROM PostHistory ph2 JOIN PostHistoryTypes pt ON pt.Id = ph2.PostHistoryTypeId WHERE ph2.PostId = p.Id ORDER BY ph2.CreationDate DESC LIMIT 1) AS LastHistoryTypeName,
         CASE
           WHEN p.ClosedDate IS NOT NULL THEN 'closed'
           WHEN EXISTS (SELECT 1 FROM PostHistory ph3 WHERE ph3.PostId = p.Id AND ph3.PostHistoryTypeId = 52) THEN 'hot'
           WHEN p.ViewCount > 100000 AND COALESCE(p.Score,0) < 0 THEN 'controversial'
           WHEN COALESCE(p.CommentCount,0) > 10 AND COALESCE(p.AnswerCount,0) = 0 THEN 'needs_answer'
           ELSE 'normal'
         END AS FlagReason
  FROM Posts p
  LEFT JOIN PostHistory ph ON ph.PostId = p.Id
  WHERE p.PostTypeId = 1
  GROUP BY p.Id, p.Title, p.PostTypeId, p.ViewCount, p.Score, p.AnswerCount, p.CommentCount, p.ClosedDate
)
SELECT
  ROW_NUMBER() OVER (ORDER BY fs.InfluenceScore DESC NULLS LAST, fs.Reputation DESC) AS Rank,
  fs.UserId,
  fs.DisplayName,
  fs.Reputation,
  fs.ReputationRank,
  fs.ReputationPercRank,
  ROUND(fs.InfluenceScore::numeric, 4) AS InfluenceScore,
  fs.AcceptanceRatePercent,
  ROUND(fs.AvgResponseSeconds, 2) AS AvgResponseSeconds,
  COALESCE(dt.DistinctTags, 0) AS DistinctTagsUsed,
  COALESCE(ut.TopTags, '') AS TopTags,
  COALESCE(rb.RecentBadges, '') AS RecentBadges,
  COALESCE(lc.LatestCommentText, '') AS LatestCommentText,
  lc.LatestCommentDate,
  COALESCE(dr.DuplicateRootCount, 0) AS DuplicateRootCount,
  COALESCE(fp.FlagReason, 'none') AS RepresentativeFlagReason,
  fp.PostId AS RepresentativeFlaggedPostId,
  COALESCE(tpc.TopIntersectCount, 0) AS TopTagsIntersectCount
FROM final_scores fs
LEFT JOIN LATERAL (
  SELECT COUNT(DISTINCT te.Tag) AS DistinctTags
  FROM tag_exploded te
  JOIN Posts p2 ON p2.Id = te.PostId
  WHERE p2.OwnerUserId = fs.UserId
) dt ON true
LEFT JOIN LATERAL (
  SELECT array_to_string(array_agg(s.Tag || ' (' || s.cnt::text || ')' ORDER BY s.cnt DESC), ', ') AS TopTags
  FROM (
    SELECT te.Tag, COUNT(*) AS cnt
    FROM tag_exploded te
    JOIN Posts p2 ON p2.Id = te.PostId
    WHERE p2.OwnerUserId = fs.UserId
    GROUP BY te.Tag
    ORDER BY cnt DESC
    LIMIT 5
  ) s
) ut ON true
LEFT JOIN LATERAL (
  SELECT array_to_string(array_agg(b2.Name || ' (' || b2.Date::text || ')' ORDER BY b2.Date DESC), '; ') AS RecentBadges
  FROM (
    SELECT b.Name, b.Date
    FROM Badges b
    WHERE b.UserId = fs.UserId
    ORDER BY b.Date DESC
    LIMIT 3
  ) b2
) rb ON true
LEFT JOIN LATERAL (
  SELECT c.Text AS LatestCommentText, c.CreationDate AS LatestCommentDate
  FROM Comments c
  JOIN Posts p2 ON p2.Id = c.PostId
  WHERE p2.OwnerUserId = fs.UserId
  ORDER BY c.CreationDate DESC
  LIMIT 1
) lc ON true
LEFT JOIN LATERAL (
  SELECT COUNT(DISTINCT p.Id) AS DuplicateRootCount
  FROM Posts p
  JOIN final_duplicate_root rdr ON rdr.PostId = p.Id
  WHERE p.OwnerUserId = fs.UserId
) dr ON true
LEFT JOIN LATERAL (
  SELECT fp.PostId, fp.FlagReason
  FROM flagged_posts fp
  WHERE fp.PostId IN (SELECT p.Id FROM Posts p WHERE p.OwnerUserId = fs.UserId)
  ORDER BY CASE WHEN fp.FlagReason = 'controversial' THEN 1 WHEN fp.FlagReason = 'needs_answer' THEN 2 WHEN fp.FlagReason = 'closed' THEN 3 ELSE 4 END, fp.PostId
  LIMIT 1
) fp ON true
LEFT JOIN (SELECT COUNT(*) AS TopIntersectCount FROM intersect_top_qv) tpc ON true
ORDER BY fs.InfluenceScore DESC NULLS LAST, fs.Reputation DESC
LIMIT 50;