-- {"query": "5002.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 979} 
WITH high_rep_users AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.Id) AS rn
    FROM Users u
    WHERE u.Reputation >= (
        SELECT percentile_cont(0.90) WITHIN GROUP (ORDER BY Reputation) FROM Users
    )
),
post_answer_counts AS (
    SELECT
        p.OwnerUserId,
        COUNT(*) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(*) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        AVG(p.Score) FILTER (WHERE p.PostTypeId = 2) AS AvgAnswerScore
    FROM Posts p
    GROUP BY p.OwnerUserId
),
badges_summary AS (
    SELECT
        b.UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        COUNT(*) AS TotalBadges
    FROM Badges b
    GROUP BY b.UserId
),
recent_activity AS (
    SELECT
        ph.UserId,
        MAX(ph.CreationDate) AS LastPostHistoryDate,
        COUNT(*) FILTER (WHERE ph.PostHistoryTypeId IN (4, 5, 6)) AS EditEvents
    FROM PostHistory ph
    WHERE ph.UserId IS NOT NULL
    GROUP BY ph.UserId
),
tag_usage AS (
    SELECT
        p.OwnerUserId,
        tg.TagName,
        COUNT(*) AS TagCount
    FROM Posts p
    JOIN LATERAL unnest(
        string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')
    ) AS tag(TagName) ON TRUE
    INNER JOIN Tags tg ON tg.TagName = tag.TagName
    WHERE p.OwnerUserId IS NOT NULL AND p.PostTypeId = 1
    GROUP BY p.OwnerUserId, tg.TagName
),
top_tags AS (
    SELECT
        tu.OwnerUserId,
        tu.TagName,
        tu.TagCount,
        ROW_NUMBER() OVER (PARTITION BY tu.OwnerUserId ORDER BY tu.TagCount DESC, tu.TagName) as TagRank
    FROM tag_usage tu
)
SELECT
    u.UserId,
    u.DisplayName,
    u.Reputation,
    pac.QuestionCount,
    pac.AnswerCount,
    COALESCE(pac.AvgAnswerScore, 0) AS AvgAnswerScore,
    bs.GoldBadges,
    bs.SilverBadges,
    bs.BronzeBadges,
    COALESCE(bs.TotalBadges,0) AS TotalBadges,
    ra.LastPostHistoryDate,
    ra.EditEvents,
    STRING_AGG(DISTINCT tt.TagName, ', ') 
        FILTER (WHERE tt.TagRank <= 3) 
        OVER (PARTITION BY u.UserId) AS TopTags,
    (
        SELECT COUNT(1)
        FROM Votes v
        WHERE v.UserId = u.UserId AND v.VoteTypeId = 2
    ) AS UpvotesCast,
    (
        SELECT COUNT(1)
        FROM Votes v
        WHERE v.UserId = u.UserId AND v.VoteTypeId = 3
    ) AS DownvotesCast,
    CASE 
        WHEN ra.LastPostHistoryDate IS NULL THEN 'No Recent Activity'
        WHEN u.LastAccessDate > ra.LastPostHistoryDate THEN 'Active'
        ELSE 'Edited'
    END AS UserStatus,
    CASE
        WHEN u.WebsiteUrl IS NOT NULL THEN LEFT(u.WebsiteUrl, 30) || 
            (CASE WHEN LENGTH(u.WebsiteUrl) > 30 THEN '...' ELSE '' END)
        ELSE 'No Website'
    END AS ShortWebsite,
    CASE 
        WHEN bs.TotalBadges IS NULL OR bs.TotalBadges = 0 THEN NULL
        ELSE ROUND(
            COALESCE(CAST(pac.AnswerCount AS FLOAT),0) / bs.TotalBadges, 2
        )
    END AS AnswersPerBadgeRatio
FROM high_rep_users u
LEFT JOIN post_answer_counts pac ON pac.OwnerUserId = u.UserId
LEFT JOIN badges_summary bs ON bs.UserId = u.UserId
LEFT JOIN recent_activity ra ON ra.UserId = u.UserId
LEFT JOIN top_tags tt ON tt.OwnerUserId = u.UserId AND tt.TagRank <= 3
ORDER BY u.Reputation DESC, u.UserId
LIMIT 100;