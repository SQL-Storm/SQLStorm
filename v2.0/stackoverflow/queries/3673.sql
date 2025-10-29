-- {"query": "3673.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2778}
WITH 
badge_counts AS (
    SELECT 
        u.Id AS UserId,
        COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        COUNT(*) AS TotalBadges
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id
),
recent_activity AS (
    SELECT 
        u.Id AS UserId,
        MAX(p.CreationDate) AS LastPostDate,
        MAX(c.CreationDate) AS LastCommentDate,
        GREATEST(
            COALESCE(MAX(p.CreationDate), CAST('1970-01-01' AS timestamp)),
            COALESCE(MAX(c.CreationDate), CAST('1970-01-01' AS timestamp))
        ) AS LastActivityDate
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '30 days'
    LEFT JOIN Comments c ON c.UserId = u.Id AND c.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '30 days'
    GROUP BY u.Id
),
post_stats AS (
    SELECT 
        u.Id AS UserId,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        AVG(p.Score) FILTER (WHERE p.PostTypeId = 1) AS AvgQuestionScore,
        AVG(p.Score) FILTER (WHERE p.PostTypeId = 2) AS AvgAnswerScore,
        SUM(p.ViewCount) FILTER (WHERE p.PostTypeId = 1) AS TotalQuestionViews,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY MAX(p.CreationDate) DESC) AS RecentPostRank
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id
),
user_tags AS (
    SELECT 
        u.Id AS UserId,
        t.TagName,
        t.Count AS TagGlobalCount,
        COUNT(*) AS TagUsageByUser
    FROM Users u
    JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 1 AND p.Tags IS NOT NULL
    CROSS JOIN LATERAL (
        SELECT regexp_split_to_table(p.Tags, '<|>') AS Tag
    ) AS split
    JOIN Tags t ON t.TagName = split.Tag
    GROUP BY u.Id, t.TagName, t.Count
),
recent_questions AS (
    SELECT 
        q.Id AS QuestionId,
        q.Title,
        q.CreationDate,
        q.Score AS QuestionScore,
        q.ViewCount,
        a.AnswerId AS TopAnswerId,
        a.AnswerScore AS TopAnswerScore,
        a.AnswerOwnerId AS TopAnswerOwnerId
    FROM Posts q
    LEFT JOIN LATERAL (
        SELECT 
            a.Id AS AnswerId,
            a.Score AS AnswerScore,
            a.OwnerUserId AS AnswerOwnerId
        FROM Posts a
        WHERE a.PostTypeId = 2 
          AND a.ParentId = q.Id
        ORDER BY a.Score DESC NULLS LAST
        LIMIT 1
    ) a ON true
    WHERE q.PostTypeId = 1
      AND q.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '7 days'
)
SELECT 
    u.Id,
    u.DisplayName,
    u.Reputation,
    bc.GoldBadges,
    bc.SilverBadges,
    bc.BronzeBadges,
    bc.TotalBadges,
    ra.LastActivityDate,
    ps.QuestionCount,
    ps.AnswerCount,
    ROUND(CAST(ps.AvgQuestionScore AS numeric),2) AS AvgQuestionScore,
    ROUND(CAST(ps.AvgAnswerScore AS numeric),2) AS AvgAnswerScore,
    ps.TotalQuestionViews,
    (SELECT ut.TagName
     FROM user_tags ut
     WHERE ut.UserId = u.Id
     ORDER BY ut.TagGlobalCount DESC, ut.TagUsageByUser DESC
     LIMIT 1) AS TopTag,
    (SELECT COUNT(*)
     FROM PostLinks pl
     JOIN Posts dup ON dup.Id = pl.RelatedPostId AND dup.PostTypeId = 1
     WHERE pl.PostId = ANY (
         SELECT Id FROM Posts WHERE OwnerUserId = u.Id AND PostTypeId = 1
     )
       AND pl.LinkTypeId = 3) AS DuplicateLinkCount,
    rq.QuestionId,
    rq.Title,
    rq.QuestionScore,
    rq.ViewCount,
    rq.TopAnswerScore,
    ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY rq.QuestionScore DESC NULLS LAST) AS QuestionRankInUser
FROM Users u
LEFT JOIN badge_counts bc ON bc.UserId = u.Id
LEFT JOIN recent_activity ra ON ra.UserId = u.Id
LEFT JOIN post_stats ps ON ps.UserId = u.Id
LEFT JOIN recent_questions rq ON rq.QuestionId = (
    SELECT p2.Id FROM Posts p2
    WHERE p2.OwnerUserId = u.Id 
      AND p2.PostTypeId = 1
    ORDER BY p2.CreationDate DESC
    LIMIT 1
)
WHERE u.Reputation > 1000
GROUP BY
    u.Id,
    u.DisplayName,
    u.Reputation,
    bc.GoldBadges,
    bc.SilverBadges,
    bc.BronzeBadges,
    bc.TotalBadges,
    ra.LastActivityDate,
    ps.QuestionCount,
    ps.AnswerCount,
    ps.AvgQuestionScore,
    ps.AvgAnswerScore,
    ps.TotalQuestionViews,
    rq.QuestionId,
    rq.Title,
    rq.CreationDate,
    rq.QuestionScore,
    rq.ViewCount,
    rq.TopAnswerScore
ORDER BY u.Reputation DESC
LIMIT 50;