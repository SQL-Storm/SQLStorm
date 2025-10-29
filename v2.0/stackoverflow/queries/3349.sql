WITH user_stats AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(u.UpVotes,0) - COALESCE(u.DownVotes,0) AS NetVotes,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS SilverBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) AS BronzeBadges,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1) AS QuestionCount,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2) AS AnswerCount,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.AcceptedAnswerId IS NOT NULL) AS AcceptedQuestions
    FROM Users u
),
tag_activity AS (
    SELECT 
        t.TagName,
        u.Id AS UserId,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS Qs,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS As,
        SUM(COALESCE(p.Score,0)) AS ScoreSum,
        MAX(p.CreationDate) AS LastActivity
    FROM Tags t
    JOIN LATERAL (
        SELECT *
        FROM Posts p
        WHERE p.Tags LIKE '%' || t.TagName || '%'
    ) p ON TRUE
    JOIN Users u ON u.Id = p.OwnerUserId
    GROUP BY t.TagName, u.Id
),
ranked_tags AS (
    SELECT 
        ta.TagName,
        ta.UserId,
        ta.Qs,
        ta.As,
        ta.ScoreSum,
        ta.LastActivity,
        ROW_NUMBER() OVER (PARTITION BY ta.TagName ORDER BY ta.ScoreSum DESC, ta.LastActivity DESC) AS rn
    FROM tag_activity ta
)
SELECT 
    us.Id,
    us.DisplayName,
    us.Reputation,
    us.NetVotes,
    us.GoldBadges,
    us.SilverBadges,
    us.BronzeBadges,
    us.QuestionCount,
    us.AnswerCount,
    us.AcceptedQuestions,
    rt.TagName,
    rt.Qs,
    rt.As,
    rt.ScoreSum,
    rt.LastActivity
FROM user_stats us
LEFT JOIN ranked_tags rt 
    ON rt.UserId = us.Id 
   AND rt.rn <= 3
WHERE us.Reputation > 1000
  AND (us.GoldBadges + us.SilverBadges + us.BronzeBadges) > 0

UNION ALL

SELECT 
    NULL AS Id,
    '---' AS DisplayName,
    NULL AS Reputation,
    NULL AS NetVotes,
    NULL AS GoldBadges,
    NULL AS SilverBadges,
    NULL AS BronzeBadges,
    NULL AS QuestionCount,
    NULL AS AnswerCount,
    NULL AS AcceptedQuestions,
    t.TagName,
    NULL AS Qs,
    NULL AS As,
    NULL AS ScoreSum,
    NULL AS LastActivity
FROM (SELECT DISTINCT TagName FROM Tags) t
WHERE NOT EXISTS (
    SELECT 1 
    FROM ranked_tags rt2 
    WHERE rt2.TagName = t.TagName 
      AND rt2.rn = 1
)
ORDER BY DisplayName;