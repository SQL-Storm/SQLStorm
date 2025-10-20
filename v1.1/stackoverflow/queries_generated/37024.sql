-- {"query": "37024.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 2190} 
WITH
-- top users by reputation and activity window
TopUsers AS (
  SELECT u.Id AS UserId, u.Reputation, u.CreationDate, u.DisplayName,
         COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS Questions,
         COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS Answers,
         COUNT(DISTINCT c.Id) AS Comments,
         MAX(p.LastActivityDate) AS LastPostActivity
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Comments c ON c.UserId = u.Id
  WHERE u.Reputation > 1000
  GROUP BY u.Id
  ORDER BY u.Reputation DESC
  LIMIT 200
),
-- heavy tags: tags with high answer-to-question ratio and many views
TagStats AS (
  SELECT t.TagName,
         t.Id AS TagId,
         t.Count AS TagCount,
         COALESCE(sum_q.QuestionCount,0) AS Questions,
         COALESCE(sum_a.AnswerCount,0) AS Answers,
         CASE WHEN COALESCE(sum_q.QuestionCount,0) = 0 THEN NULL
              ELSE ROUND(COALESCE(sum_a.AnswerCount,0)::numeric / sum_q.QuestionCount, 3) END AS AnswerToQuestionRatio,
         COALESCE(sum_views.Views,0) AS TotalViews
  FROM Tags t
  LEFT JOIN (
    SELECT unnest(string_to_array(substring(p.Tags,2,length(p.Tags)-2), '><')) AS TagName, count(*) AS QuestionCount
    FROM Posts p
    WHERE p.PostTypeId = 1
    GROUP BY 1
  ) sum_q ON sum_q.TagName = t.TagName
  LEFT JOIN (
    SELECT unnest(string_to_array(substring(q.Tags,2,length(q.Tags)-2), '><')) AS TagName, count(a.Id) AS AnswerCount
    FROM Posts q
    JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    WHERE q.PostTypeId = 1
    GROUP BY 1
  ) sum_a ON sum_a.TagName = t.TagName
  LEFT JOIN (
    SELECT unnest(string_to_array(substring(p.Tags,2,length(p.Tags)-2), '><')) AS TagName, SUM(p.ViewCount) AS Views
    FROM Posts p
    WHERE p.PostTypeId = 1
    GROUP BY 1
  ) sum_views ON sum_views.TagName = t.TagName
  WHERE t.Count > 100
),
-- complex post scoring combining recency, score, favorites, answers, comments and accepted answers
PostScores AS (
  SELECT p.Id AS PostId,
         p.PostTypeId,
         p.Title,
         p.CreationDate,
         p.Score,
         p.ViewCount,
         p.AnswerCount,
         p.CommentCount,
         p.FavoriteCount,
         p.AcceptedAnswerId,
         COALESCE(v.UpVotes,0) AS UpVotes,
         COALESCE(v.DownVotes,0) AS DownVotes,
         -- recency weight: posts in last year get boost, older decay
         CASE
           WHEN p.CreationDate >= now() - INTERVAL '90 days' THEN 1.5
           WHEN p.CreationDate >= now() - INTERVAL '1 year' THEN 1.2
           ELSE 1.0
         END AS RecencyWeight,
         -- community engagement: normalized combination
         (
           (GREATEST(p.Score,0)::numeric * 2.5)
           + (LEAST(p.ViewCount,100000)::numeric / 1000)
           + (LEAST(p.AnswerCount,50)::numeric * 3)
           + (LEAST(p.CommentCount,200)::numeric * 1.2)
           + (LEAST(p.FavoriteCount,500)::numeric * 4)
           + (CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 20 ELSE 0 END)
           + (COALESCE(v.UpVotes,0) - COALESCE(v.DownVotes,0)) * 2
         ) * CASE
               WHEN p.PostTypeId = 1 THEN 1.1
               WHEN p.PostTypeId = 2 THEN 0.9
               ELSE 0.5
             END * 
         CASE WHEN p.CreationDate IS NULL THEN 1 ELSE 1 END
         AS RawEngagementScore
  FROM Posts p
  LEFT JOIN (
    SELECT PostId,
           SUM(CASE WHEN VoteTypeId = 2 THEN 1 WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) FILTER (WHERE VoteTypeId = 2) AS UpVotes,
           SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) FILTER (WHERE VoteTypeId = 3) AS DownVotes
    FROM Votes
    GROUP BY PostId
  ) v ON v.PostId = p.Id
  WHERE p.PostTypeId IN (1,2)
),
-- join posts to tags mapping exploded
PostTagMap AS (
  SELECT p.Id AS PostId, trim(tg) AS TagName
  FROM Posts p
  CROSS JOIN LATERAL (
    SELECT unnest(string_to_array(substring(p.Tags,2,length(p.Tags)-2), '><')) AS tg
  ) x
  WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL AND p.Tags <> ''
),
-- aggregated per-tag top posts and user participation
TagTopPosts AS (
  SELECT ts.TagName, ts.TagId, ts.TagCount, ts.AnswerToQuestionRatio, ts.TotalViews,
         pt.PostId, ps.Title, ps.RawEngagementScore,
         ROW_NUMBER() OVER (PARTITION BY ts.TagName ORDER BY ps.RawEngagementScore DESC NULLS LAST) AS RankWithinTag
  FROM TagStats ts
  JOIN PostTagMap pt ON pt.TagName = ts.TagName
  JOIN PostScores ps ON ps.PostId = pt.PostId
  WHERE ps.RawEngagementScore IS NOT NULL
),
-- compute correlated owner stats for top posts and their owners
OwnerStats AS (
  SELECT u.Id AS UserId,
         u.DisplayName,
         COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS UserQuestions,
         COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS UserAnswers,
         SUM(COALESCE(p.Score,0)) AS TotalPostScore,
         AVG(COALESCE(p.Score,0)) FILTER (WHERE p.PostTypeId IN (1,2)) AS AvgPostScore,
         MAX(p.CreationDate) AS LatestPost
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  GROUP BY u.Id
),
-- recent edit churn: posts with many history entries in short time
EditChurn AS (
  SELECT ph.PostId,
         COUNT(*) AS Revisions,
         MIN(ph.CreationDate) AS FirstRev,
         MAX(ph.CreationDate) AS LastRev,
         (EXTRACT(EPOCH FROM (MAX(ph.CreationDate) - MIN(ph.CreationDate))) / 3600)::numeric AS HoursSpan,
         ROUND(COUNT(*)::numeric / NULLIF(GREATEST(EXTRACT(EPOCH FROM (MAX(ph.CreationDate) - MIN(ph.CreationDate))),1),0),6) AS RevsPerSecond -- raw density
  FROM PostHistory ph
  WHERE ph.CreationDate >= now() - INTERVAL '2 years'
  GROUP BY ph.PostId
  HAVING COUNT(*) >= 5
),
-- final selection: combine tag metrics, top posts per tag, owner stats, churn and related duplicates/links
Final AS (
  SELECT tt.TagName,
         tt.TagCount,
         tt.AnswerToQuestionRatio,
         tt.TotalViews,
         tt.PostId,
         tt.Title,
         ROUND(tt.RawEngagementScore,3) AS EngagementScore,
         o.UserId,
         o.DisplayName AS OwnerName,
         o.UserQuestions,
         o.UserAnswers,
         o.AvgPostScore,
         ec.Revisions,
         ec.HoursSpan,
         CASE WHEN pl_dup.DupCount IS NULL THEN 0 ELSE pl_dup.DupCount END AS DuplicateLinksOut,
         CASE WHEN pl_in.DupInCount IS NULL THEN 0 ELSE pl_in.DupInCount END AS DuplicateLinksIn
  FROM TagTopPosts tt
  LEFT JOIN Posts p ON p.Id = tt.PostId
  LEFT JOIN OwnerStats o ON o.UserId = p.OwnerUserId
  LEFT JOIN EditChurn ec ON ec.PostId = tt.PostId
  LEFT JOIN (
    SELECT pl.PostId, COUNT(*) AS DupCount FROM PostLinks pl WHERE pl.LinkTypeId = 3 GROUP BY pl.PostId
  ) pl_dup ON pl_dup.PostId = tt.PostId
  LEFT JOIN (
    SELECT pl.RelatedPostId AS PostId, COUNT(*) AS DupInCount FROM PostLinks pl WHERE pl.LinkTypeId = 3 GROUP BY pl.RelatedPostId
  ) pl_in ON pl_in.PostId = tt.PostId
  WHERE tt.RankWithinTag <= 3
)
SELECT
  f.TagName,
  f.TagCount,
  f.AnswerToQuestionRatio,
  f.TotalViews,
  f.PostId,
  f.Title,
  f.EngagementScore,
  f.OwnerName,
  f.UserQuestions,
  f.UserAnswers,
  ROUND(f.AvgPostScore::numeric,3) AS AvgPostScore,
  COALESCE(f.Revisions,0) AS RevisionsLast2Years,
  COALESCE(f.HoursSpan,0)::numeric(10,2) AS RevisionHoursSpan,
  f.DuplicateLinksOut,
  f.DuplicateLinksIn,
  -- rank across tags by normalized score: scale by tag count and answer ratio
  RANK() OVER (ORDER BY (f.EngagementScore * (1 + COALESCE(f.AnswerToQuestionRatio,0)) * LOG(GREATEST(f.TagCount,10))) DESC) AS GlobalTagPostRank
FROM Final f
ORDER BY GlobalTagPostRank, f.TagName, f.EngagementScore DESC
LIMIT 500;