-- {"query": "3814.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2517} 

WITH UserPostStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        AVG(p.Score) FILTER (WHERE p.PostTypeId IN (1,2)) AS AvgScore,
        SUM(CASE WHEN p.PostTypeId = 2 AND p.Id = q.AcceptedAnswerId THEN 1 ELSE 0 END) AS AcceptedAnswerCount,
        MAX(p.CreationDate) AS LastPostDate
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Posts q ON p.PostTypeId = 2 AND p.ParentId = q.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
UserBadgeStats AS (
    SELECT 
        b.UserId,
        COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        SUM(CASE WHEN b.TagBased = 1 THEN 1 ELSE 0 END) AS TagBasedBadgeCount
    FROM Badges b
    GROUP BY b.UserId
),
UserVoteStats AS (
    SELECT 
        v.UserId,
        COUNT(*) FILTER (WHERE v.VoteTypeId = 2) AS UpVotesCast,
        COUNT(*) FILTER (WHERE v.VoteTypeId = 3) AS DownVotesCast,
        COUNT(*) FILTER (WHERE v.VoteTypeId = 5) AS FavoritesCast
    FROM Votes v
    GROUP BY v.UserId
),
RecentActivity AS (
    SELECT 
        u.Id AS UserId,
        GREATEST(
            COALESCE(u.LastAccessDate, '1970-01-01'::timestamp),
            COALESCE(p.LastActivityDate, '1970-01-01'::timestamp),
            COALESCE(c.CreationDate, '1970-01-01'::timestamp)
        ) AS MostRecentActivity
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
),
TagUsage AS (
    SELECT 
        p.OwnerUserId AS UserId,
        UNNEST(string_to_array(trim(both '><' FROM p.Tags), '><')) AS Tag,
        COUNT(*) AS TagUseCount
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
    GROUP BY p.OwnerUserId, Tag
),
TopTags AS (
    SELECT 
        UserId,
        STRING_AGG(Tag || ':' || TagUseCount, ', ' ORDER BY TagUseCount DESC) AS TopTagList
    FROM (
        SELECT 
            UserId,
            Tag,
            TagUseCount,
            ROW_NUMBER() OVER (PARTITION BY UserId ORDER BY TagUseCount DESC) AS rn
        FROM TagUsage
    ) t
    WHERE rn <= 5
    GROUP BY UserId
)
SELECT 
    ups.UserId,
    ups.DisplayName,
    ups.Reputation,
    ups.QuestionCount,
    ups.AnswerCount,
    ROUND(ups.AvgScore::numeric,2) AS AvgScore,
    ups.AcceptedAnswerCount,
    COALESCE(ubs.GoldBadges,0) AS GoldBadges,
    COALESCE(ubs.SilverBadges,0) AS SilverBadges,
    COALESCE(ubs.BronzeBadges,0) AS BronzeBadges,
    COALESCE(ubs.TagBasedBadgeCount,0) AS TagBasedBadgeCount,
    COALESCE(uvs.UpVotesCast,0) - COALESCE(uvs.DownVotesCast,0) AS NetVotesCast,
    COALESCE(ra.MostRecentActivity, ups.LastPostDate) AS MostRecentActivity,
    COALESCE(tt.TopTagList, '') AS TopTags
FROM UserPostStats ups
LEFT JOIN UserBadgeStats ubs ON ubs.UserId = ups.UserId
LEFT JOIN UserVoteStats uvs ON uvs.UserId = ups.UserId
LEFT JOIN RecentActivity ra ON ra.UserId = ups.UserId
LEFT JOIN TopTags tt ON tt.UserId = ups.UserId
WHERE 
    (ups.QuestionCount > 0 OR ups.AnswerCount > 0)
    AND ups.Reputation > 1000
    AND (COALESCE(ubs.GoldBadges,0) + COALESCE(ubs.SilverBadges,0) + COALESCE(ubs.BronzeBadges,0)) >= 5
ORDER BY 
    ups.Reputation DESC,
    NetVotesCast DESC,
    (ups.QuestionCount + ups.AnswerCount) DESC
LIMIT 100

UNION ALL

SELECT 
    u.Id,
    u.DisplayName,
    u.Reputation,
    0,
    0,
    NULL,
    0,
    0,
    0,
    0,
    0,
    NULL,
    NULL,
    ''
FROM Users u
WHERE NOT EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = u.Id)
  AND u.Reputation BETWEEN 500 AND 1000
ORDER BY Reputation DESC
LIMIT 20;
