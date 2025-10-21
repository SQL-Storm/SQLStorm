-- {"query": "55041.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2048, "output_tokens": 1139} 

WITH 
-- 1. Expand post tags into a normalized table
expanded_tags AS (
    SELECT 
        p.Id            AS PostId,
        p.PostTypeId,
        p.OwnerUserId   AS OwnerUserId,
        p.Score         AS PostScore,
        p.CreationDate  AS PostCreation,
        unnest(string_to_array(
              substring(p.Tags FROM 2 FOR length(p.Tags)-2), 
              '><'))::varchar(35) AS TagName
    FROM Posts p
    WHERE p.PostTypeId = 1               -- only questions
      AND p.Tags IS NOT NULL
),

-- 2. Gather answer statistics per tag and user
answer_stats AS (
    SELECT 
        et.TagName,
        a.OwnerUserId,
        COUNT(*)                                   AS AnswerCount,
        AVG(a.Score)                               AS AvgAnswerScore,
        MAX(a.CreationDate)                        AS LastAnswerDate,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
    FROM expanded_tags et
    JOIN Posts a ON a.ParentId = et.PostId                -- a is an answer to the question
                  AND a.PostTypeId = 2
    LEFT JOIN Votes v ON v.PostId = a.Id
    GROUP BY et.TagName, a.OwnerUserId
),

-- 3. Compute user reputation and badge counts
user_profile AS (
    SELECT 
        u.Id               AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
        MAX(u.LastAccessDate)                     AS LastSeen
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),

-- 4. Recent activity window (last 30 days) per tag
recent_activity AS (
    SELECT 
        et.TagName,
        COUNT(DISTINCT p.Id)                              AS RecentQuestions,
        COUNT(DISTINCT a.Id)                              AS RecentAnswers,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS RecentUpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS RecentDownVotes
    FROM expanded_tags et
    LEFT JOIN Posts p ON p.Id = et.PostId
                      AND p.CreationDate >= now() - interval '30 days'
    LEFT JOIN Posts a ON a.ParentId = et.PostId
                      AND a.PostTypeId = 2
                      AND a.CreationDate >= now() - interval '30 days'
    LEFT JOIN Votes v ON v.PostId IN (p.Id, a.Id)
                     AND v.CreationDate >= now() - interval '30 days'
    GROUP BY et.TagName
),

-- 5. Top users per tag (ranked by reputation, then answer count)
ranked_users AS (
    SELECT 
        asg.TagName,
        up.UserId,
        up.DisplayName,
        up.Reputation,
        asg.AnswerCount,
        asg.AvgAnswerScore,
        asg.UpVotes,
        asg.DownVotes,
        ROW_NUMBER() OVER (PARTITION BY asg.TagName 
                           ORDER BY up.Reputation DESC, asg.AnswerCount DESC) AS rn
    FROM answer_stats asg
    JOIN user_profile up ON up.UserId = asg.OwnerUserId
)

SELECT 
    ru.TagName,
    ru.DisplayName,
    ru.Reputation,
    ru.AnswerCount,
    ROUND(ru.AvgAnswerScore, 2)      AS AvgAnswerScore,
    ru.UpVotes,
    ru.DownVotes,
    up.GoldBadges,
    up.SilverBadges,
    up.BronzeBadges,
    ra.RecentQuestions,
    ra.RecentAnswers,
    ra.RecentUpVotes,
    ra.RecentDownVotes,
    up.LastSeen
FROM ranked_users ru
JOIN user_profile up ON up.UserId = ru.UserId
LEFT JOIN recent_activity ra ON ra.TagName = ru.TagName
WHERE ru.rn <= 5               -- top‑5 contributors per tag
ORDER BY ru.TagName, ru.rn;
