-- {"query": "3870.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1377} 
WITH 
    -- 1️⃣ Gather post aggregates per user
    user_post_stats AS (
        SELECT 
            p.OwnerUserId AS UserId,
            COUNT(*) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
            COUNT(*) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
            SUM(p.Score) FILTER (WHERE p.PostTypeId = 1) AS QuestionScoreSum,
            SUM(p.Score) FILTER (WHERE p.PostTypeId = 2) AS AnswerScoreSum,
            SUM(p.ViewCount) FILTER (WHERE p.PostTypeId = 1) AS QuestionViewSum,
            COUNT(p.AcceptedAnswerId) FILTER (WHERE p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL) AS AcceptedAnswers,
            COALESCE(SUM(p.FavoriteCount),0) AS FavoriteSum
        FROM Posts p
        WHERE p.OwnerUserId IS NOT NULL
        GROUP BY p.OwnerUserId
    ),
    
    -- 2️⃣ Extract badge influence per user
    user_badge_stats AS (
        SELECT 
            b.UserId,
            COUNT(*) AS TotalBadges,
            COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
            COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
            COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges,
            COUNT(*) FILTER (WHERE b.TagBased = 1) AS TagBasedBadges
        FROM Badges b
        GROUP BY b.UserId
    ),
    
    -- 3️⃣ Compute vote‑derived points per user (upvotes * 10 – downvotes * 2)
    user_vote_points AS (
        SELECT 
            v.UserId,
            SUM(CASE WHEN vt.Id = 2 THEN 10      -- UpMod
                     WHEN vt.Id = 3 THEN -2      -- DownMod
                     ELSE 0 END) AS VotePoints
        FROM Votes v
        JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
        WHERE v.UserId IS NOT NULL
        GROUP BY v.UserId
    ),
    
    -- 4️⃣ Derive top three tags a user has interacted with (questions asked or answered)
    user_top_tags AS (
        SELECT 
            u.Id AS UserId,
            ARRAY_AGG(t.TagName ORDER BY tag_usage DESC LIMIT 3) AS TopTags
        FROM Users u
        JOIN Posts p ON p.OwnerUserId = u.Id
        LEFT JOIN LATERAL (
            SELECT unnest(string_to_array(trim(both '<>' FROM p.Tags), '><')) AS Tag
        ) AS taglist ON true
        LEFT JOIN Tags t ON t.TagName = taglist.Tag
        GROUP BY u.Id
    ),
    
    -- 5️⃣ Assemble a dense rank based on a composite score
    user_composite AS (
        SELECT 
            u.Id,
            u.DisplayName,
            COALESCE(ups.QuestionScoreSum,0) * 0.3
          + COALESCE(ups.AnswerScoreSum,0) * 0.4
          + COALESCE(ups.FavoriteSum,0) * 0.1
          + COALESCE(ubs.GoldBadges,0) * 20
          + COALESCE(ubs.SilverBadges,0) * 10
          + COALESCE(ubs.BronzeBadges,0) * 5
          + COALESCE(uvp.VotePoints,0) * 0.05
          AS CompositeScore,
            ups.QuestionCount,
            ups.AnswerCount,
            ups.AcceptedAnswers,
            COALESCE(ubs.TotalBadges,0) AS TotalBadges,
            COALESCE(ut.TopTags, ARRAY[]::varchar[]) AS TopTags
        FROM Users u
        LEFT JOIN user_post_stats ups ON ups.UserId = u.Id
        LEFT JOIN user_badge_stats ubs ON ubs.UserId = u.Id
        LEFT JOIN user_vote_points uvp ON uvp.UserId = u.Id
        LEFT JOIN user_top_tags ut ON ut.UserId = u.Id
    )
SELECT 
    uc.Id,
    uc.DisplayName,
    ROUND(uc.CompositeScore,2) AS CompositeScore,
    RANK() OVER (ORDER BY uc.CompositeScore DESC) AS RankByScore,
    uc.QuestionCount,
    uc.AnswerCount,
    uc.AcceptedAnswers,
    uc.TotalBadges,
    uc.TopTags,
    CASE 
        WHEN uc.CompositeScore >= 1000 THEN 'Elite'
        WHEN uc.CompositeScore >= 500  THEN 'Pro'
        WHEN uc.CompositeScore >= 200  THEN 'Rising'
        ELSE 'Novice'
    END AS Tier,
    /* Calculate a “reputation drift” as the difference between current Rep and the score‑derived estimate */
    (u.Reputation - uc.CompositeScore) AS ReputationDrift
FROM user_composite uc
JOIN Users u ON u.Id = uc.Id
WHERE uc.CompositeScore IS NOT NULL
   AND (u.CreationDate < CURRENT_DATE - INTERVAL '1 year')   -- exclude brand‑new accounts
ORDER BY uc.CompositeScore DESC
LIMIT 100
UNION ALL
SELECT 
    NULL AS Id,
    '--- Summary Row ---' AS DisplayName,
    NULL,
    NULL,
    SUM(uc.QuestionCount) AS QuestionCount,
    SUM(uc.AnswerCount)   AS AnswerCount,
    SUM(uc.AcceptedAnswers) AS AcceptedAnswers,
    SUM(uc.TotalBadges)   AS TotalBadges,
    ARRAY_AGG(DISTINCT tag) FILTER (WHERE tag IS NOT NULL) AS TopTags,
    NULL,
    NULL
FROM user_composite uc
LEFT JOIN LATERAL UNNEST(uc.TopTags) AS tag ON true;