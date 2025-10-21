-- {"query": "25035.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2732} 

WITH q AS (
   SELECT p.Id,
          p.OwnerUserId,
          p.Score,
          p.CreationDate,
          p.ViewCount,
          p.Title,
          p.Tags,
          COALESCE(p.AcceptedAnswerId,0) AS AcceptedAns,
          ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn_q
   FROM Posts p
   WHERE p.PostTypeId = 1
     AND p.CreationDate >= CURRENT_DATE - INTERVAL '365 days'
),
a AS (
   SELECT p.Id,
          p.ParentId,
          p.OwnerUserId,
          p.Score,
          p.CreationDate,
          ROW_NUMBER() OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC) AS rn_a
   FROM Posts p
   WHERE p.PostTypeId = 2
),
badge_counts AS (
   SELECT u.Id AS UserId,
          SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS gold_cnt,
          SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS silver_cnt,
          SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS bronze_cnt
   FROM Users u
   LEFT JOIN Badges b ON b.UserId = u.Id
   GROUP BY u.Id
),
tag_usage AS (
   SELECT t.TagName,
          COUNT(*) FILTER (WHERE p.PostTypeId = 1) AS question_cnt,
          COUNT(*) FILTER (WHERE p.PostTypeId = 2) AS answer_cnt,
          SUM(p.Score) AS total_score
   FROM Tags t
   LEFT JOIN Posts p
     ON t.TagName = ANY (string_to_array(trim(both '<>' FROM COALESCE(p.Tags,'')), '><'))
   GROUP BY t.TagName
),
vote_summary AS (
   SELECT v.PostId,
          SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS upvotes,
          SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS downvotes,
          MAX(v.CreationDate) AS last_vote_date
   FROM Votes v
   GROUP BY v.PostId
)
SELECT 
   u.Id AS UserId,
   u.DisplayName,
   COALESCE(qc.question_cnt,0)          AS TotalQuestions,
   COALESCE(ac.answer_cnt,0)            AS TotalAnswers,
   COALESCE(bc.gold_cnt,0)              AS GoldBadges,
   COALESCE(bc.silver_cnt,0)            AS SilverBadges,
   COALESCE(bc.bronze_cnt,0)            AS BronzeBadges,
   COALESCE(vs.upvotes,0) - COALESCE(vs.downvotes,0) AS NetVotes,
   CASE 
      WHEN u.Reputation >= 20000 THEN 'Legendary'
      WHEN u.Reputation >= 10000 THEN 'Expert'
      WHEN u.Reputation >= 2000  THEN 'Intermediate'
      ELSE 'Beginner'
   END                                 AS ReputationTier,
   STRING_AGG(DISTINCT t.TagName, ', ') FILTER (WHERE t.TagName IS NOT NULL) AS TopTags,
   MAX(p.CreationDate) FILTER (WHERE p.PostTypeId = 1) AS LastQuestionDate,
   MAX(p.CreationDate) FILTER (WHERE p.PostTypeId = 2) AS LastAnswerDate,
   ROW_NUMBER() OVER (ORDER BY COALESCE(qc.question_cnt,0) + COALESCE(ac.answer_cnt,0) DESC) AS ActivityRank
FROM Users u
LEFT JOIN (
   SELECT OwnerUserId, COUNT(*) AS question_cnt
   FROM q
   GROUP BY OwnerUserId
) qc ON qc.OwnerUserId = u.Id
LEFT JOIN (
   SELECT OwnerUserId, COUNT(*) AS answer_cnt
   FROM a
   GROUP BY OwnerUserId
) ac ON ac.OwnerUserId = u.Id
LEFT JOIN badge_counts bc ON bc.UserId = u.Id
LEFT JOIN vote_summary vs ON vs.PostId = (
   SELECT Id FROM Posts p2
   WHERE p2.OwnerUserId = u.Id
   ORDER BY p2.CreationDate DESC
   LIMIT 1
)
LEFT JOIN Posts p ON p.OwnerUserId = u.Id
LEFT JOIN Tags t ON t.TagName = ANY (string_to_array(trim(both '<>' FROM COALESCE(p.Tags,'')), '><'))
GROUP BY 
   u.Id, u.DisplayName,
   qc.question_cnt, ac.answer_cnt,
   bc.gold_cnt, bc.silver_cnt, bc.bronze_cnt,
   vs.upvotes, vs.downvotes
HAVING COUNT(*) > 0
UNION ALL
SELECT 
   NULL AS UserId,
   'TOTAL' AS DisplayName,
   SUM(COALESCE(qc.question_cnt,0)),
   SUM(COALESCE(ac.answer_cnt,0)),
   SUM(COALESCE(bc.gold_cnt,0)),
   SUM(COALESCE(bc.silver_cnt,0)),
   SUM(COALESCE(bc.bronze_cnt,0)),
   SUM(COALESCE(vs.upvotes,0) - COALESCE(vs.downvotes,0)),
   NULL,
   NULL,
   NULL,
   NULL,
   NULL
FROM Users u
LEFT JOIN (
   SELECT OwnerUserId, COUNT(*) AS question_cnt
   FROM q
   GROUP BY OwnerUserId
) qc ON qc.OwnerUserId = u.Id
LEFT JOIN (
   SELECT OwnerUserId, COUNT(*) AS answer_cnt
   FROM a
   GROUP BY OwnerUserId
) ac ON ac.OwnerUserId = u.Id
LEFT JOIN badge_counts bc ON bc.UserId = u.Id
LEFT JOIN vote_summary vs ON vs.PostId = (
   SELECT Id FROM Posts p2
   WHERE p2.OwnerUserId = u.Id
   ORDER BY p2.CreationDate DESC
   LIMIT 1
);
