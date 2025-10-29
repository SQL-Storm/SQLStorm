-- {"query": "3673.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2778} 

WITH 
-- aggregate badge counts per user
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
-- recent activity per user (last 30 days)
recent_activity AS (
    SELECT 
        u.Id AS UserId,
        MAX(p.CreationDate) AS LastPostDate,
        MAX(c.CreationDate) AS LastCommentDate,
        GREATEST(
            COALESCE(MAX(p.CreationDate), '1970-01-01'::timestamp),
            COALESCE(MAX(c.CreationDate), '1970-01-01'::timestamp)
        ) AS LastActivityDate
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.CreationDate >= CURRENT_DATE - INTERVAL '30 days'
    LEFT JOIN Comments c ON c.UserId = u.Id AND c.CreationDate >= CURRENT_DATE - INTERVAL '30 days'
    GROUP BY u.Id
),
-- compute per‑user post statistics, using window functions
post_stats AS (
    SELECT 
        u.Id AS UserId,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        AVG(p.Score) FILTER (WHERE p.PostTypeId = 1) AS AvgQuestionScore,
        AVG(p.Score) FILTER (WHERE p.PostTypeId = 2) AS AvgAnswerScore,
        SUM(p.ViewCount) FILTER (WHERE p.PostTypeId = 1) AS TotalQuestionViews,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY p.CreationDate DESC) AS RecentPostRank
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id
),
-- tags used by user in their questions, with tag popularity
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
-- recent posts (questions) with their top voted answers
recent_questions AS (
    SELECT 
        q.Id AS QuestionId,
        q.Title,
        q.CreationDate,
        q.Score AS QuestionScore,
        q.ViewCount,
        COALESCE(a.AnswerId, NULL) AS TopAnswerId,
        COALESCE(a.AnswerScore, NULL) AS TopAnswerScore,
        COALESCE(a.AnswerOwnerId, NULL) AS TopAnswerOwnerId
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
      AND q.CreationDate >= CURRENT_DATE - INTERVAL '7 days'
)
-- final result combining everything
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
    ROUND(ps.AvgQuestionScore::numeric,2) AS AvgQuestionScore,
    ROUND(ps.AvgAnswerScore::numeric,2) AS AvgAnswerScore,
    ps.TotalQuestionViews,
    -- most popular tag for the user (by global count, break ties by usage)
    (SELECT ut.TagName
     FROM user_tags ut
     WHERE ut.UserId = u.Id
     ORDER BY ut.TagGlobalCount DESC, ut.TagUsageByUser DESC
     LIMIT 1) AS TopTag,
    -- number of questions that have a duplicate link pointing to another question
    (SELECT COUNT(*)
     FROM PostLinks pl
     JOIN Posts dup ON dup.Id = pl.RelatedPostId AND dup.PostTypeId = 1
     WHERE pl.PostId = ANY (
         SELECT Id FROM Posts WHERE OwnerUserId = u.Id AND PostTypeId = 1
     )
       AND pl.LinkTypeId = 3) AS DuplicateLinkCount,
    -- compute a composite activity score using window function rank over recent_questions
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
    SELECT Id FROM Posts p
    WHERE p.OwnerUserId = u.Id 
      AND p.PostTypeId = 1
    ORDER BY p.CreationDate DESC
    LIMIT 1
)
WHERE u.Reputation > 1000
ORDER BY u.Reputation DESC
LIMIT 50;
