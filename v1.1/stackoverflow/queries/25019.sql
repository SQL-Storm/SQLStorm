WITH 
UserStats AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(u.UpVotes,0) - COALESCE(u.DownVotes,0) AS NetVoteScore,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS SilverBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) AS BronzeBadges,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1) AS QuestionCount,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2) AS AnswerCount
    FROM Users u
    WHERE u.Reputation > 1000
),
TagInfo AS (
    SELECT 
        t.TagName,
        t.Count AS TagUsage,
        COALESCE(LENGTH(p_ex.Body),0) AS ExcerptLength,
        COALESCE(LENGTH(p_wk.Body),0) AS WikiLength
    FROM Tags t
    LEFT JOIN Posts p_ex ON p_ex.Id = t.ExcerptPostId
    LEFT JOIN Posts p_wk ON p_wk.Id = t.WikiPostId
    WHERE t.Count > 500
),
RecentActivity AS (
    SELECT 
        u.Id AS UserId,
        MAX(p.CreationDate)  AS LastPostDate,
        MAX(v.CreationDate)  AS LastVoteDate,
        MAX(c.CreationDate)  AS LastCommentDate
    FROM Users u
    LEFT JOIN Posts   p ON p.OwnerUserId = u.Id
    LEFT JOIN Votes   v ON v.UserId      = u.Id
    LEFT JOIN Comments c ON c.UserId     = u.Id
    GROUP BY u.Id
),
Combined AS (
    SELECT 
        us.Id,
        us.DisplayName,
        us.Reputation,
        us.NetVoteScore,
        us.GoldBadges,
        us.SilverBadges,
        us.BronzeBadges,
        us.QuestionCount,
        us.AnswerCount,
        ra.LastPostDate,
        ra.LastVoteDate,
        ra.LastCommentDate,
        ROW_NUMBER() OVER (ORDER BY us.Reputation DESC, us.NetVoteScore DESC) AS RankByRep
    FROM UserStats us
    LEFT JOIN RecentActivity ra ON ra.UserId = us.Id
)
SELECT 
    c.Id,
    c.DisplayName,
    c.Reputation,
    c.NetVoteScore,
    c.GoldBadges,
    c.SilverBadges,
    c.BronzeBadges,
    c.QuestionCount,
    c.AnswerCount,
    CASE 
        WHEN GREATEST(COALESCE(c.LastPostDate, TIMESTAMP '1970-01-01'),
                      COALESCE(c.LastVoteDate, TIMESTAMP '1970-01-01'),
                      COALESCE(c.LastCommentDate, TIMESTAMP '1970-01-01')) > u.CreationDate
        THEN EXTRACT(day FROM (GREATEST(COALESCE(c.LastPostDate, TIMESTAMP '1970-01-01'),
                                       COALESCE(c.LastVoteDate, TIMESTAMP '1970-01-01'),
                                       COALESCE(c.LastCommentDate, TIMESTAMP '1970-01-01')) - u.CreationDate))
        ELSE NULL
    END AS DaysSinceLastActivity,
    ti.TagName,
    ti.TagUsage,
    ti.ExcerptLength,
    ti.WikiLength
FROM Combined c
JOIN Users u ON u.Id = c.Id
LEFT JOIN LATERAL (
    SELECT 
        t.TagName,
        t.Count      AS TagUsage,
        COALESCE(LENGTH(p_ex.Body),0) AS ExcerptLength,
        COALESCE(LENGTH(p_wk.Body),0) AS WikiLength
    FROM Tags t
    JOIN Posts p ON p.Tags ILIKE ('%' || '<' || t.TagName || '>' || '%')
    LEFT JOIN Posts p_ex ON p_ex.Id = t.ExcerptPostId
    LEFT JOIN Posts p_wk ON p_wk.Id = t.WikiPostId
    GROUP BY t.Id, t.TagName, t.Count, p_ex.Body, p_wk.Body
    ORDER BY t.Count DESC
    LIMIT 1
) ti ON TRUE
WHERE c.RankByRep <= 10

UNION ALL

SELECT 
    NULL AS Id,
    '---' AS DisplayName,
    NULL AS Reputation,
    NULL AS NetVoteScore,
    NULL AS GoldBadges,
    NULL AS SilverBadges,
    NULL AS BronzeBadges,
    NULL AS QuestionCount,
    NULL AS AnswerCount,
    NULL AS DaysSinceLastActivity,
    NULL AS TagName,
    NULL AS TagUsage,
    NULL AS ExcerptLength,
    NULL AS WikiLength

ORDER BY 
    Reputation DESC NULLS LAST,
    NetVoteScore DESC
LIMIT 20;