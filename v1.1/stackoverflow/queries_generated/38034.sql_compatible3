WITH recent_users AS (
  SELECT u.Id AS UserId, u.DisplayName, u.Reputation, u.CreationDate
  FROM Users u
  WHERE u.CreationDate >= (SELECT MAX(CreationDate) - INTERVAL '365 days' FROM Users)
),
top_tags AS (
  SELECT t.TagName, t.Count
  FROM Tags t
  WHERE t.Count > (SELECT PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY Count) FROM Tags)
),
question_tags AS (
  SELECT p.Id AS QuestionId,
         p.OwnerUserId,
         p.CreationDate,
         p.Score,
         p.ViewCount,
         CASE
           WHEN p.Tags IS NULL THEN NULL
           ELSE TRIM(BOTH '<' FROM TRIM(BOTH '>' FROM p.Tags))
         END AS tag_string
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= (SELECT MAX(CreationDate) - INTERVAL '365 days' FROM Posts WHERE PostTypeId = 1)
    AND p.Tags IS NOT NULL
),
exploded_qtags AS (
  SELECT qt.QuestionId,
         qt.OwnerUserId,
         qt.CreationDate,
         qt.Score,
         qt.ViewCount,
         LOWER(TRIM(BOTH '|' FROM t.part)) AS TagName
  FROM question_tags qt
  JOIN LATERAL (
    WITH RECURSIVE splitter(rest, part) AS (
      SELECT REPLACE(qt.tag_string, '><', '|||') || '|||' AS rest, NULL
      UNION ALL
      SELECT
        CASE
          WHEN POSITION('|||' IN rest) = 0 THEN ''
          ELSE SUBSTRING(rest FROM POSITION('|||' IN rest) + 3)
        END,
        CASE
          WHEN POSITION('|||' IN rest) = 0 THEN rest
          ELSE SUBSTRING(rest FROM 1 FOR POSITION('|||' IN rest) - 1)
        END
      FROM splitter
      WHERE rest IS NOT NULL AND rest <> ''
    )
    SELECT DISTINCT part
    FROM splitter
    WHERE part IS NOT NULL AND part <> ''
  ) t ON true
),
filtered_qtags AS (
  SELECT e.QuestionId,
         e.OwnerUserId,
         e.CreationDate,
         e.Score,
         e.ViewCount,
         e.TagName
  FROM exploded_qtags e
  JOIN top_tags tt ON tt.TagName = e.TagName
),
answers AS (
  SELECT a.Id AS AnswerId, a.ParentId AS QuestionId, a.OwnerUserId, a.CreationDate, a.Score
  FROM Posts a
  WHERE a.PostTypeId = 2
    AND a.CreationDate >= (SELECT MAX(CreationDate) - INTERVAL '365 days' FROM Posts WHERE PostTypeId = 2)
),
first_answer AS (
  SELECT a.QuestionId,
         MIN(a.CreationDate) AS FirstAnswerDate,
         COUNT(*) AS AnswerCountYear
  FROM answers a
  GROUP BY a.QuestionId
),
votes_agg AS (
  SELECT v.PostId,
         SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
         SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
         SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END) AS Favorites,
         COUNT(*) AS TotalVotes,
         SUM(CASE WHEN v.CreationDate >= (SELECT MAX(CreationDate) - INTERVAL '30 days' FROM Votes) THEN 1 ELSE 0 END) AS Votes30d
  FROM Votes v
  GROUP BY v.PostId
),
comments_agg AS (
  SELECT c.PostId,
         COUNT(*) AS CommentCount,
         AVG(COALESCE(c.Score, 0)) AS AvgCommentScore
  FROM Comments c
  WHERE c.CreationDate >= (SELECT MAX(CreationDate) - INTERVAL '365 days' FROM Comments)
  GROUP BY c.PostId
),
close_events AS (
  SELECT ph.PostId,
         COUNT(*) AS CloseEvents,
         MAX(ph.CreationDate) AS LastCloseDate,
         MAX(CASE WHEN ph.Comment ~ '^[0-9]+$' THEN CAST(ph.Comment AS INTEGER) END) AS LastCloseReasonId
  FROM PostHistory ph
  WHERE ph.PostHistoryTypeId IN (10,35)
  GROUP BY ph.PostId
),
dup_links AS (
  SELECT pl.PostId, COUNT(*) AS DuplicateLinks
  FROM PostLinks pl
  WHERE pl.LinkTypeId = 3
  GROUP BY pl.PostId
),
hot_bumps AS (
  SELECT ph.PostId,
         SUM(CASE WHEN ph.PostHistoryTypeId = 50 THEN 1 ELSE 0 END) AS CommunityBumps,
         SUM(CASE WHEN ph.PostHistoryTypeId = 52 THEN 1 ELSE 0 END) AS SelectedHot,
         SUM(CASE WHEN ph.PostHistoryTypeId = 53 THEN 1 ELSE 0 END) AS RemovedHot
  FROM PostHistory ph
  WHERE ph.PostHistoryTypeId IN (50,52,53)
  GROUP BY ph.PostId
),
owner_stats AS (
  SELECT u.Id AS UserId,
         SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsCount,
         SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersCount,
         AVG(p.Score) AS AvgPostScore,
         SUM(p.Score) AS SumPostScore
  FROM Users u
  JOIN Posts p ON p.OwnerUserId = u.Id
  GROUP BY u.Id
),
tag_popularity AS (
  SELECT fqt.TagName,
         COUNT(DISTINCT fqt.QuestionId) AS QuestionsWithTag,
         AVG(q.Score) AS AvgQuestionScoreWithTag,
         AVG(q.ViewCount) AS AvgViewsWithTag
  FROM filtered_qtags fqt
  JOIN Posts q ON q.Id = fqt.QuestionId
  GROUP BY fqt.TagName
),
q_metrics AS (
  SELECT q.Id AS QuestionId,
         q.OwnerUserId,
         q.Score,
         q.ViewCount,
         q.CreationDate,
         COALESCE(v.UpVotes,0) AS UpVotes,
         COALESCE(v.DownVotes,0) AS DownVotes,
         COALESCE(v.Favorites,0) AS Favorites,
         COALESCE(v.TotalVotes,0) AS TotalVotes,
         COALESCE(v.Votes30d,0) AS Votes30d,
         COALESCE(c.CommentCount,0) AS CommentCount,
         COALESCE(c.AvgCommentScore,0) AS AvgCommentScore,
         fa.FirstAnswerDate AS FirstAnswerDate,
         COALESCE(fa.AnswerCountYear,0) AS AnswerCountYear,
         EXTRACT(EPOCH FROM (fa.FirstAnswerDate - q.CreationDate)) / 3600.0 AS HoursToFirstAnswer,
         COALESCE(cl.CloseEvents,0) AS CloseEvents,
         cl.LastCloseDate,
         cl.LastCloseReasonId,
         COALESCE(dl.DuplicateLinks,0) AS DuplicateLinks,
         COALESCE(hb.CommunityBumps,0) AS CommunityBumps,
         COALESCE(hb.SelectedHot,0) AS SelectedHot,
         COALESCE(hb.RemovedHot,0) AS RemovedHot
  FROM Posts q
  LEFT JOIN votes_agg v ON v.PostId = q.Id
  LEFT JOIN comments_agg c ON c.PostId = q.Id
  LEFT JOIN first_answer fa ON fa.QuestionId = q.Id
  LEFT JOIN close_events cl ON cl.PostId = q.Id
  LEFT JOIN dup_links dl ON dl.PostId = q.Id
  LEFT JOIN hot_bumps hb ON hb.PostId = q.Id
  WHERE q.PostTypeId = 1
    AND q.CreationDate >= (SELECT MAX(CreationDate) - INTERVAL '365 days' FROM Posts WHERE PostTypeId = 1)
),
ranked_questions AS (
  SELECT qm.QuestionId,
         qm.OwnerUserId,
         qm.Score,
         qm.ViewCount,
         qm.CreationDate,
         qm.UpVotes,
         qm.DownVotes,
         qm.Favorites,
         qm.TotalVotes,
         qm.Votes30d,
         qm.CommentCount,
         qm.AvgCommentScore,
         qm.FirstAnswerDate,
         qm.AnswerCountYear,
         qm.HoursToFirstAnswer,
         qm.CloseEvents,
         qm.LastCloseDate,
         qm.LastCloseReasonId,
         qm.DuplicateLinks,
         qm.CommunityBumps,
         qm.SelectedHot,
         qm.RemovedHot,
         ROW_NUMBER() OVER (ORDER BY
            COALESCE(qm.UpVotes - qm.DownVotes,0) * 2
            + LEAST(qm.ViewCount, 10000) / 100
            + COALESCE(qm.CommentCount,0) * 0.5
            + COALESCE(10.0 / NULLIF(qm.HoursToFirstAnswer,0), 0)
            + COALESCE(qm.SelectedHot,0) * 20
            - COALESCE(qm.RemovedHot,0) * 10
            - COALESCE(qm.CloseEvents,0) * 5 DESC,
            qm.CreationDate DESC
         ) AS RankScorePos,
         ROW_NUMBER() OVER (PARTITION BY qm.OwnerUserId ORDER BY qm.Score DESC, qm.ViewCount DESC) AS OwnerTopRank
  FROM q_metrics qm
),
user_enriched AS (
  SELECT ru.UserId,
         ru.DisplayName,
         ru.Reputation,
         os.QuestionsCount,
         os.AnswersCount,
         os.AvgPostScore,
         os.SumPostScore
  FROM recent_users ru
  LEFT JOIN owner_stats os ON os.UserId = ru.UserId
),
final_join AS (
  SELECT rq.QuestionId,
         rq.OwnerUserId,
         ue.DisplayName AS OwnerName,
         ue.Reputation AS OwnerReputation,
         ue.QuestionsCount,
         ue.AnswersCount,
         rq.Score,
         rq.ViewCount,
         rq.UpVotes,
         rq.DownVotes,
         rq.Favorites,
         rq.TotalVotes,
         rq.Votes30d,
         rq.CommentCount,
         rq.AvgCommentScore,
         rq.FirstAnswerDate,
         rq.AnswerCountYear,
         rq.HoursToFirstAnswer,
         rq.CloseEvents,
         rq.LastCloseDate,
         rq.LastCloseReasonId,
         rq.DuplicateLinks,
         rq.CommunityBumps,
         rq.SelectedHot,
         rq.RemovedHot,
         rq.RankScorePos,
         rq.OwnerTopRank
  FROM ranked_questions rq
  LEFT JOIN user_enriched ue ON ue.UserId = rq.OwnerUserId
),
per_tag_scoring AS (
  SELECT fqt.TagName,
         fj.QuestionId,
         fj.OwnerUserId,
         fj.OwnerName,
         fj.OwnerReputation,
         fj.Score,
         fj.ViewCount,
         fj.UpVotes,
         fj.DownVotes,
         fj.TotalVotes,
         fj.CommentCount,
         fj.HoursToFirstAnswer,
         fj.RankScorePos,
         ts.QuestionsWithTag,
         ts.AvgQuestionScoreWithTag,
         ts.AvgViewsWithTag,
         (COALESCE(fj.UpVotes - fj.DownVotes,0) * 1.5
          + LEAST(fj.ViewCount, 20000) / 200
          + COALESCE(5.0 / NULLIF(fj.HoursToFirstAnswer,0), 0)
          + CASE WHEN fj.OwnerReputation >= 10000 THEN 2 ELSE 0 END) AS TagAdjustedScore
  FROM filtered_qtags fqt
  JOIN final_join fj ON fj.QuestionId = fqt.QuestionId
  JOIN tag_popularity ts ON ts.TagName = fqt.TagName
),
tag_leaders AS (
  SELECT TagName,
         QuestionId,
         OwnerUserId,
         OwnerName,
         OwnerReputation,
         Score,
         ViewCount,
         UpVotes,
         DownVotes,
         TotalVotes,
         CommentCount,
         HoursToFirstAnswer,
         RankScorePos,
         QuestionsWithTag,
         AvgQuestionScoreWithTag,
         AvgViewsWithTag,
         TagAdjustedScore,
         ROW_NUMBER() OVER (PARTITION BY TagName ORDER BY TagAdjustedScore DESC, RankScorePos ASC) AS rn
  FROM per_tag_scoring
)
SELECT tl.TagName,
       tl.QuestionId,
       tl.OwnerUserId,
       tl.OwnerName,
       tl.OwnerReputation,
       tl.Score,
       tl.ViewCount,
       tl.UpVotes,
       tl.DownVotes,
       tl.TotalVotes,
       tl.CommentCount,
       ROUND(CAST(tl.HoursToFirstAnswer AS NUMERIC), 2) AS HoursToFirstAnswer,
       tl.RankScorePos,
       tl.QuestionsWithTag,
       ROUND(CAST(tl.AvgQuestionScoreWithTag AS NUMERIC), 2) AS AvgQuestionScoreWithTag,
       ROUND(CAST(tl.AvgViewsWithTag AS NUMERIC), 2) AS AvgViewsWithTag,
       ROUND(CAST(tl.TagAdjustedScore AS NUMERIC), 2) AS TagAdjustedScore
FROM tag_leaders tl
WHERE tl.rn <= 5
ORDER BY tl.TagName, tl.TagAdjustedScore DESC, tl.RankScorePos ASC;