-- {"query": "37012.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 1848} 
WITH
-- recent active questions with tag array
Questions AS (
  SELECT p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount,
         COALESCE(string_to_array(substring(p.Tags,2,length(p.Tags)-2), '><'), ARRAY[]::varchar[]) AS Tags,
         p.OwnerUserId, p.AnswerCount, p.CommentCount
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= now() - interval '2 years'
),
-- latest edit info per post
LastEdits AS (
  SELECT ph.PostId,
         max(ph.CreationDate) AS LastEditDate,
         count(*) FILTER (WHERE ph.PostHistoryTypeId IN (5,6,4)) AS EditCount
  FROM PostHistory ph
  WHERE ph.PostHistoryTypeId IN (4,5,6,7,8,9,24)
  GROUP BY ph.PostId
),
-- aggregated vote stats per post
PostVotes AS (
  SELECT v.PostId,
         SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
         SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
         SUM(CASE WHEN v.VoteTypeId = 1 THEN 1 ELSE 0 END) AS AcceptedFlags,
         COUNT(*) AS TotalVotes,
         MAX(v.CreationDate) AS LastVoteDate
  FROM Votes v
  GROUP BY v.PostId
),
-- badge counts and top badge class per user
UserBadges AS (
  SELECT b.UserId,
         COUNT(*) AS BadgeCount,
         MAX(b.Date) AS LastBadgeDate,
         MAX(b.Class) FILTER (WHERE b.Class IS NOT NULL) AS TopBadgeClass
  FROM Badges b
  GROUP BY b.UserId
),
-- answer stats per question
AnswerStats AS (
  SELECT p.ParentId AS QuestionId,
         COUNT(*) AS AnswerTotal,
         SUM(CASE WHEN p.Score >= 10 THEN 1 ELSE 0 END) AS HighScoreAnswers,
         AVG(p.Score) AS AvgAnswerScore,
         MAX(p.Score) AS MaxAnswerScore
  FROM Posts p
  WHERE p.PostTypeId = 2
  GROUP BY p.ParentId
),
-- link neighborhood for questions (links to and from)
PostLinkNeighborhood AS (
  SELECT pl.PostId AS QuestionId,
         COUNT(*) FILTER (WHERE pl.LinkTypeId = 1) AS OutgoingLinks,
         COUNT(*) FILTER (WHERE pl.LinkTypeId = 3) AS DuplicateLinks,
         COUNT(DISTINCT pl.RelatedPostId) AS DistinctLinkedPosts
  FROM PostLinks pl
  JOIN Posts q ON q.Id = pl.PostId AND q.PostTypeId = 1
  GROUP BY pl.PostId
),
-- heavy commenters on the question
TopCommenters AS (
  SELECT c.PostId,
         json_agg(json_build_object('UserId', c.UserId, 'Display', c.UserDisplayName, 'Count', cnt) ORDER BY cnt DESC, MAX(c.CreationDate) DESC) AS CommenterList
  FROM (
    SELECT c.PostId, c.UserId, c.UserDisplayName, COUNT(*) AS cnt, MAX(c.CreationDate) AS CreationDate
    FROM Comments c
    GROUP BY c.PostId, c.UserId, c.UserDisplayName
  ) c
  GROUP BY c.PostId
),
-- compute per-question composite "engagement score"
Engagement AS (
  SELECT q.Id,
         (COALESCE(q.Score,0) * 3
          + COALESCE(pv.UpVotes,0) * 2
          - COALESCE(pv.DownVotes,0) * 1.5
          + LEAST(COALESCE(q.ViewCount,0)::numeric / 1000, 50) * 1.2
          + COALESCE(q.AnswerCount,0) * 5
          + COALESCE(as_.HighScoreAnswers,0) * 4
          + COALESCE(q.CommentCount,0) * 1.5
          + GREATEST(0, (extract(epoch from (now() - COALESCE(le.LastEditDate,q.CreationDate))) / 86400)::numeric * -0.05)
         ) AS EngagementScore
  FROM Questions q
  LEFT JOIN PostVotes pv ON pv.PostId = q.Id
  LEFT JOIN AnswerStats as_ ON as_.QuestionId = q.Id
  LEFT JOIN LastEdits le ON le.PostId = q.Id
),
-- tag co-occurrence matrix (top tags per question)
TagExplode AS (
  SELECT q.Id AS QuestionId, unnest(q.Tags) AS Tag
  FROM Questions q
),
TagPairs AS (
  SELECT te1.Tag AS TagA, te2.Tag AS TagB, COUNT(*) AS CoOccur
  FROM TagExplode te1
  JOIN TagExplode te2 ON te1.QuestionId = te2.QuestionId AND te1.Tag <> te2.Tag
  GROUP BY te1.Tag, te2.Tag
),
TopTagPairs AS (
  SELECT TagA, TagB, CoOccur
  FROM TagPairs
  ORDER BY CoOccur DESC
  LIMIT 100
),
-- final selection: pick a diverse set of high-engagement questions with heavy interactions
SelectedQuestions AS (
  SELECT q.*, e.EngagementScore, pv.UpVotes, pv.DownVotes, pv.TotalVotes, pv.LastVoteDate,
         ub.BadgeCount, ub.TopBadgeClass, as_.AnswerTotal, as_.AvgAnswerScore, pln.OutgoingLinks, pln.DuplicateLinks,
         tc.CommenterList
  FROM Questions q
  JOIN Engagement e ON e.Id = q.Id
  LEFT JOIN PostVotes pv ON pv.PostId = q.Id
  LEFT JOIN UserBadges ub ON ub.UserId = q.OwnerUserId
  LEFT JOIN AnswerStats as_ ON as_.QuestionId = q.Id
  LEFT JOIN PostLinkNeighborhood pln ON pln.QuestionId = q.Id
  LEFT JOIN TopCommenters tc ON tc.PostId = q.Id
),
Ranked AS (
  SELECT sq.*,
         row_number() OVER (ORDER BY sq.EngagementScore DESC NULLS LAST, sq.ViewCount DESC NULLS LAST) AS RankByEngagement,
         dense_rank() OVER (PARTITION BY COALESCE(sq.OwnerUserId, -1) ORDER BY sq.EngagementScore DESC) AS OwnerDenseRank
  FROM SelectedQuestions sq
)
SELECT
  r.RankByEngagement,
  r.Id AS QuestionId,
  r.Title,
  r.CreationDate,
  r.EngagementScore,
  r.Score AS QuestionScore,
  r.ViewCount,
  r.AnswerTotal,
  round(r.AvgAnswerScore::numeric,2) AS AvgAnswerScore,
  r.UpVotes,
  r.DownVotes,
  r.TotalVotes,
  r.CommentCount,
  r.BadgeCount,
  r.TopBadgeClass,
  r.OutgoingLinks,
  r.DuplicateLinks,
  r.CommenterList,
  -- correlated subquery: sample top answers with author and score (limit 3)
  (SELECT json_agg(json_build_object(
            'AnswerId', a.Id,
            'Score', a.Score,
            'OwnerUserId', a.OwnerUserId,
            'OwnerDisplayName', a.OwnerDisplayName,
            'CreationDate', a.CreationDate
          ) ORDER BY a.Score DESC, a.CreationDate ASC)
   FROM Posts a
   WHERE a.ParentId = r.Id AND a.PostTypeId = 2
   LIMIT 3) AS TopAnswersSample,
  -- tag list
  (SELECT array_agg(tg) FROM (SELECT unnest(r.Tags) AS tg ORDER BY tg) s) AS Tags,
  -- related popular linked questions
  (SELECT json_agg(json_build_object('RelatedId', p2.Id, 'Title', p2.Title, 'Score', p2.Score, 'LinkType', lt.Name))
   FROM PostLinks pl
   JOIN Posts p2 ON p2.Id = pl.RelatedPostId
   LEFT JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
   WHERE pl.PostId = r.Id
   ORDER BY p2.Score DESC NULLS LAST
   LIMIT 5
  ) AS TopLinkedPosts
FROM Ranked r
WHERE r.RankByEngagement <= 200
  AND r.OwnerDenseRank <= 5    -- avoid too many from same owner
  AND r.EngagementScore IS NOT NULL
ORDER BY r.EngagementScore DESC, r.ViewCount DESC;