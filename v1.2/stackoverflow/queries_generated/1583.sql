-- {"query": "1583.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.5, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1504} 

WITH RecentHighRepAskers AS (
    SELECT u.Id, u.DisplayName, u.Reputation,
           ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.CreationDate) as Rn
    FROM Users u
    WHERE u.Reputation > 10000
      AND u.LastAccessDate > CURRENT_DATE - INTERVAL '90 days'
),
QuestionDetails AS (
    SELECT p.Id, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, p.Tags,
           COALESCE(NULLIF(p.Title, ''), '[No Title]') AS TitleNonNull,
           -- count tagged as specific popular tags
           (SELECT COUNT(*)
            FROM unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) AS tag
            WHERE tag IN ('sql', 'performance', 'optimization')) AS PopularTagCount
    FROM Posts p
    WHERE p.PostTypeId = 1 -- Question
      AND p.Score >= 5
),
BadgeRanking AS (
    SELECT b.UserId, b.Name, b.Class,
           RANK() OVER (PARTITION BY b.UserId ORDER BY b.Date DESC) as RankPerUser
    FROM Badges b
    WHERE b.Class IN (1,2)
),
ClosedQuestionsErrors AS (
  SELECT ph.PostId,
         MIN(CAST(ph.Comment AS int)) FILTER (WHERE ph.PostHistoryTypeId = 10 AND ph.Comment ~ '^\d+$') AS CloseReasonId,
         COUNT(DISTINCT ph.UserId) FILTER (WHERE ph.PostHistoryTypeId = 10) AS UniqueCloseVoters,
         MAX(ph.CreationDate) AS LastCloseDate
  FROM PostHistory ph
  WHERE ph.PostHistoryTypeId = 10
    AND ph.PostId IN (SELECT Id FROM QuestionDetails)
  GROUP BY ph.PostId
),
AnsweredDetails AS (
  SELECT a.Id, a.ParentId, a.Score, a.CreationDate, u.DisplayName as AnswererName, u.Reputation as AnswererRep,
         ROW_NUMBER() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC) as AnswerRank
  FROM Posts a
  LEFT JOIN Users u ON a.OwnerUserId = u.Id
  WHERE a.PostTypeId = 2
),
AnswersWithConditionalStat AS (
  SELECT ad.*,
         CASE
           WHEN ad.Score > 10 THEN LENGTH(ad.AnswererName) * ad.AnswererRep * 0.1
           ELSE ad.Score * 2 END AS AdjustedScoreMetric
  FROM AnsweredDetails ad
),
RecentVotesCTE AS (
  SELECT v.PostId, v.VoteTypeId,
         COUNT(*) FILTER (WHERE v.VoteTypeId = 2) AS UpvotesLast60Days,
         COUNT(*) FILTER (WHERE v.VoteTypeId = 3) AS DownvotesLast60Days,
         MAX(v.CreationDate) AS LastVoteDate
  FROM Votes v
  WHERE v.CreationDate > CURRENT_DATE - INTERVAL '60 days'
  GROUP BY v.PostId, v.VoteTypeId
),
PopularQuestionsWithContext AS (
    SELECT q.Id as QuestionId, q.TitleNonNull, q.Score, q.ViewCount, q.Tags, q.PopularTagCount,
           rh.DisplayDate,
           ARRAY_AGG(br.Name ORDER BY br.RankPerUser LIMIT 3) FILTER (WHERE br.UserId = q.OwnerUserId) AS TopBadges,
           cqe.CloseReasonId, cqe.UniqueCloseVoters, cqe.LastCloseDate,
           COALESCE(rv.UpvotesLast60Days,0) AS RecentUpvotes,
           COALESCE(rv.DownvotesLast60Days,0) AS RecentDownvotes,
           awc.AnswerRank, awc.AdjustedScoreMetric,
           rec.UsernameLastEditor,
           CONCAT(
              LEFT(QD.TitleNonNull, 100),
              '...', CASE WHEN qp.pop_remarkable_over_threshold IS NOT NULL AND qp.pop_remarkable_over_threshold THEN ' (Highly Popular Post!)' ELSE '' END
           ) AS SnippetTitle
    FROM QuestionDetails q
    LEFT JOIN (
       SELECT PostId, MAX(CreationDate) AS DisplayDate, MAX(UserDisplayName) AS UsernameLastEditor
       FROM PostHistory
       GROUP BY PostId
    ) rh ON rh.PostId = q.Id
    LEFT JOIN BadgeRanking br ON br.UserId = q.OwnerUserId AND br.RankPerUser <= 3
    LEFT JOIN ClosedQuestionsErrors cqe ON cqe.PostId = q.Id
    LEFT JOIN RecentVotesCTE rv ON rv.PostId = q.Id
    LEFT JOIN LATERAL (
       SELECT aw.* FROM AnswersWithConditionalStat aw WHERE aw.ParentId = q.Id ORDER BY aw.AnswerRank FETCH FIRST 1 ROW ONLY
    ) awc ON TRUE
    LEFT JOIN LATERAL (
      SELECT CASE WHEN q.ViewCount > 100000 THEN TRUE ELSE FALSE END AS pop_remarkable_over_threshold
    ) qp ON TRUE
)
SELECT pqc.*,
       CONCAT(
         '[', COALESCE(string_agg(DISTINCT br19.Name, ', ' ORDER BY br19.Name), '') , ']'
       ) AS RecentBronzeBadges,
       STRING_AGG(DISTINCT
            CASE WHEN b.Class = 1 THEN b.Name ELSE NULL END, '; ' ORDER BY b.Date DESC) FILTER (WHERE b.Class = 1) AS GoldBadgesAwardedRecently,
       phType.Name AS LastPostEditType,
       CASE
           WHEN pqc.UniqueCloseVoters > 2 AND pqc.CloseReasonId IN (101,102,103,104,105) THEN 'Possibly Controversial'
           WHEN pqc.RecentUpvotes > pqc.RecentDownvotes * 3 THEN 'Well Liked'
           ELSE 'Ordinary'
       END AS PopularityCategory
FROM PopularQuestionsWithContext pqc
LEFT JOIN PostHistory phM ON phM.PostId = pqc.QuestionId
LEFT JOIN PostHistoryTypes phType ON phType.Id = phM.PostHistoryTypeId
LEFT JOIN Badges b ON b.UserId IN (pqc.QuestionId)  -- eccentric join for benchmark
LEFT JOIN Badges br19 ON br19.UserId IN (SELECT UserId FROM BadgeRanking WHERE RankPerUser = 19)
WHERE EXISTS (
    SELECT 1 FROM RecentHighRepAskers rhra WHERE rhra.Id = pqc.OwnerUserId
)
GROUP BY pqc.QuestionId, pqc.TitleNonNull, pqc.Score, pqc.ViewCount, pqc.Tags, pqc.PopularTagCount, pqc.DisplayDate,
         pqc.TopBadges, pqc.CloseReasonId, pqc.UniqueCloseVoters, pqc.LastCloseDate, pqc.RecentUpvotes,
         pqc.RecentDownvotes, pqc.AnswerRank, pqc.AdjustedScoreMetric, pqc.UsernameLastEditor, pqc.SnippetTitle,
         phType.Name, pqc.UniqueCloseVoters, pqc.CloseReasonId, pqc.RecentUpvotes, pqc.RecentDownvotes;
