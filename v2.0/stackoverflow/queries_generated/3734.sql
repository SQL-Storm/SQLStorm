-- {"query": "3734.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2301} 

WITH
    q AS (
        SELECT
            p.Id                      AS QuestionId,
            p.OwnerUserId,
            p.CreationDate,
            p.Score                   AS QuestionScore,
            p.ViewCount,
            p.Tags,
            COALESCE(p.FavoriteCount,0) AS Favorites,
            p.AnswerCount,
            p.AcceptedAnswerId,
            p.Title
        FROM Posts p
        WHERE p.PostTypeId = 1
    ),
    a AS (
        SELECT
            p.Id                      AS AnswerId,
            p.ParentId                AS QuestionId,
            p.OwnerUserId,
            p.CreationDate,
            p.Score                   AS AnswerScore,
            p.CommentCount,
            p.LastEditDate
        FROM Posts p
        WHERE p.PostTypeId = 2
    ),
    user_votes AS (
        SELECT
            v.UserId,
            SUM(CASE v.VoteTypeId WHEN 2 THEN 1 WHEN 3 THEN -1 ELSE 0 END)                AS NetVotes,
            COUNT(*) FILTER (WHERE v.VoteTypeId = 5)                                      AS FavoritesGiven,
            COUNT(*) FILTER (WHERE v.VoteTypeId = 8)                                      AS BountiesStarted
        FROM Votes v
        GROUP BY v.UserId
    ),
    badge_points AS (
        SELECT
            b.UserId,
            SUM(CASE b.Class WHEN 1 THEN 100 WHEN 2 THEN 50 ELSE 10 END)                 AS BadgeScore
        FROM Badges b
        GROUP BY b.UserId
    ),
    tag_usage AS (
        SELECT
            u.Id                                          AS UserId,
            COUNT(DISTINCT unnest(string_to_array(trim(both '><' FROM q.Tags), '><'))) AS DistinctTagCount
        FROM Users u
        LEFT JOIN q ON q.OwnerUserId = u.Id
        GROUP BY u.Id
    ),
    user_stats AS (
        SELECT
            u.Id,
            u.DisplayName,
            u.Reputation,
            COALESCE(uv.NetVotes,0)         AS NetVotes,
            COALESCE(bp.BadgeScore,0)       AS BadgeScore,
            COALESCE(tu.DistinctTagCount,0) AS DistinctTagCount,
            ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, COALESCE(uv.NetVotes,0) DESC) AS ReputationRank
        FROM Users u
        LEFT JOIN user_votes uv   ON uv.UserId = u.Id
        LEFT JOIN badge_points bp ON bp.UserId = u.Id
        LEFT JOIN tag_usage tu    ON tu.UserId = u.Id
    ),
    top_answered_questions AS (
        SELECT
            q.QuestionId,
            q.Title,
            q.OwnerUserId,
            q.AnswerCount,
            q.QuestionScore,
            ROW_NUMBER() OVER (PARTITION BY q.OwnerUserId ORDER BY q.AnswerCount DESC, q.QuestionScore DESC) AS rn
        FROM q
        WHERE q.AnswerCount > 0
    )
SELECT
    us.Id,
    us.DisplayName,
    us.Reputation,
    us.NetVotes,
    us.BadgeScore,
    us.DistinctTagCount,
    us.ReputationRank,
    COALESCE(taq.Title,'<no answered question>')   AS TopAnsweredQuestionTitle,
    COALESCE(taq.AnswerCount,0)                    AS TopAnswerCount,
    COALESCE(taq.QuestionScore,0)                  AS TopQuestionScore,
    CASE
        WHEN us.Reputation >= 20000 THEN 'Legendary'
        WHEN us.Reputation >= 10000 THEN 'Expert'
        WHEN us.Reputation >= 5000  THEN 'Experienced'
        ELSE 'Novice'
    END                                            AS ReputationTier,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = us.Id AND p.PostTypeId = 1 AND p.CreationDate > CURRENT_DATE - INTERVAL '30 days') AS RecentQuestions,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = us.Id AND p.PostTypeId = 2 AND p.CreationDate > CURRENT_DATE - INTERVAL '30 days') AS RecentAnswers,
    (SELECT AVG(a.AnswerScore)
       FROM a
       WHERE a.QuestionId IN (SELECT q.QuestionId FROM q WHERE q.OwnerUserId = us.Id)
    )                                            AS AvgScoreOfAnswersToOwnQuestions
FROM user_stats us
LEFT JOIN top_answered_questions taq
     ON taq.OwnerUserId = us.Id AND taq.rn = 1
WHERE (us.Reputation > 1000 OR us.BadgeScore > 0)
  AND (us.EmailHash IS NOT NULL OR us.WebsiteUrl IS NOT NULL)
ORDER BY us.ReputationRank
LIMIT 100;
