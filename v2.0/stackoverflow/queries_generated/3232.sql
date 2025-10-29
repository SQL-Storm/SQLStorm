-- {"query": "3232.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 3481} 

WITH
  BadgeCounts AS (
    SELECT
      UserId,
      SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS Gold,
      SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS Silver,
      SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS Bronze
    FROM Badges
    GROUP BY UserId
  ),
  RecentActivity AS (
    SELECT
      p.OwnerUserId,
      MAX(p.CreationDate) AS LastPostDate,
      MAX(p.Score) FILTER (WHERE p.PostTypeId = 1) AS MaxQuestionScore,
      MAX(p.Score) FILTER (WHERE p.PostTypeId = 2) AS MaxAnswerScore
    FROM Posts p
    WHERE p.CreationDate >= CURRENT_DATE - INTERVAL '90 days'
    GROUP BY p.OwnerUserId
  ),
  UserSummary AS (
    SELECT
      u.Id,
      u.DisplayName,
      u.Reputation,
      COALESCE(u.Views,0)                              AS Views,
      COALESCE(u.UpVotes,0) - COALESCE(u.DownVotes,0)  AS NetVoteBalance,
      COALESCE(bc.Gold,0)                              AS GoldBadges,
      COALESCE(bc.Silver,0)                            AS SilverBadges,
      COALESCE(bc.Bronze,0)                            AS BronzeBadges,
      COALESCE(qcnt.QuestionCount,0)                  AS QuestionCount,
      COALESCE(acnt.AnswerCount,0)                    AS AnswerCount,
      ra.LastPostDate,
      ra.MaxQuestionScore,
      ra.MaxAnswerScore,
      ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS ReputationRank
    FROM Users u
    LEFT JOIN BadgeCounts bc
           ON bc.UserId = u.Id
    LEFT JOIN (
      SELECT OwnerUserId, COUNT(*) AS QuestionCount
      FROM Posts
      WHERE PostTypeId = 1
      GROUP BY OwnerUserId
    ) qcnt
           ON qcnt.OwnerUserId = u.Id
    LEFT JOIN (
      SELECT OwnerUserId, COUNT(*) AS AnswerCount
      FROM Posts
      WHERE PostTypeId = 2
      GROUP BY OwnerUserId
    ) acnt
           ON acnt.OwnerUserId = u.Id
    LEFT JOIN RecentActivity ra
           ON ra.OwnerUserId = u.Id
  ),
  TopTags AS (
    SELECT
      t.TagName,
      t.Count                           AS TagUseCount,
      AVG(COALESCE(p.Score,0))          AS AvgScore,
      SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionPosts,
      SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerPosts,
      ROW_NUMBER() OVER (ORDER BY t.Count DESC)          AS TagRank
    FROM Tags t
    LEFT JOIN Posts p
      ON p.Tags LIKE CONCAT('%<', t.TagName, '>%')
    GROUP BY t.TagName, t.Count
    HAVING COUNT(*) > 0
  )
SELECT
  us.Id,
  us.DisplayName,
  us.Reputation,
  us.Views,
  us.NetVoteBalance,
  us.GoldBadges,
  us.SilverBadges,
  us.BronzeBadges,
  us.QuestionCount,
  us.AnswerCount,
  us.LastPostDate,
  us.MaxQuestionScore,
  us.MaxAnswerScore,
  us.ReputationRank,
  tt.TagName,
  tt.TagUseCount,
  tt.AvgScore,
  tt.QuestionPosts,
  tt.AnswerPosts,
  tt.TagRank
FROM UserSummary us
LEFT JOIN TopTags tt
  ON tt.TagRank <= 5
  AND EXISTS (
        SELECT 1
        FROM Posts p
        WHERE p.OwnerUserId = us.Id
          AND p.Tags LIKE CONCAT('%<', tt.TagName, '>%')
        LIMIT 1
      )
WHERE us.Reputation >= 50000
   OR us.GoldBadges >= 10
   OR us.ReputationRank <= 100
ORDER BY us.Reputation DESC,
         us.GoldBadges DESC,
         tt.TagRank NULLS LAST
OFFSET 0 ROWS FETCH NEXT 200 ROWS ONLY

UNION ALL

SELECT
  NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL
WHERE NOT EXISTS (SELECT 1 FROM Users WHERE Reputation >= 50000);
