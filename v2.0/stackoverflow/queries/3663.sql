WITH UserStats AS (
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
        (SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 2)   AS UpVotesGiven,
        (SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 3)   AS DownVotesGiven,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS RepRank
    FROM Users u
    WHERE u.Id IS NOT NULL
),
RecentActivity AS (
    SELECT 
        p.OwnerUserId AS UserId,
        MAX(p.CreationDate) AS LastPostDate,
        MAX(c.CreationDate) AS LastCommentDate
    FROM Posts p
    LEFT JOIN Comments c ON c.UserId = p.OwnerUserId
    GROUP BY p.OwnerUserId
),
TagPopularity AS (
    SELECT 
        t.TagName,
        t.Count,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS TagRank
    FROM Tags t
    WHERE t.TagName IS NOT NULL
),
Combined AS (
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
        us.UpVotesGiven,
        us.DownVotesGiven,
        COALESCE(ra.LastPostDate, ra.LastCommentDate) AS LastActivity,
        CASE 
            WHEN us.AnswerCount = 0 THEN NULL
            ELSE CAST(us.AnswerCount AS DOUBLE PRECISION) / NULLIF(us.QuestionCount,0)
        END AS AnswerToQuestionRatio,
        (us.GoldBadges*5 + us.SilverBadges*3 + us.BronzeBadges) AS BadgeScore,
        us.RepRank
    FROM UserStats us
    LEFT JOIN RecentActivity ra ON ra.UserId = us.Id
)
SELECT 
    c.Id,
    c.DisplayName,
    c.Reputation,
    c.NetVotes,
    c.GoldBadges,
    c.SilverBadges,
    c.BronzeBadges,
    c.QuestionCount,
    c.AnswerCount,
    c.AnswerToQuestionRatio,
    c.BadgeScore,
    c.RepRank,
    COALESCE(c.LastActivity, TIMESTAMP '1970-01-01') AS LastActivity,
    STRING_AGG(t.TagName, ', ') FILTER (WHERE t.TagName IS NOT NULL) AS TopTags
FROM Combined c
LEFT JOIN PostLinks pl 
    ON pl.PostId = (
        SELECT p.Id 
        FROM Posts p 
        WHERE p.OwnerUserId = c.Id AND p.PostTypeId = 1 
        ORDER BY p.Score DESC 
        LIMIT 1
    )
LEFT JOIN Posts tp ON tp.Id = pl.RelatedPostId
LEFT JOIN (
    -- emulate lateral tag splitting without LATERAL by producing one row per tag per post
    SELECT p.Id AS post_id,
           TRIM(BOTH '<>' FROM tag_fragment) AS tag_fragment
    FROM Posts p
    CROSS JOIN LATERAL (
        -- for compatibility, use a regexp-based split emulation where supported; if not supported replace with appropriate split function
        SELECT regexp_split_to_table(p.Tags, '><') AS tag_fragment
    ) s
) tags_raw ON tags_raw.post_id = tp.Id
LEFT JOIN Tags t 
    ON t.TagName = tags_raw.tag_fragment
WHERE c.Reputation > 50000
  AND (c.AnswerToQuestionRatio IS NULL OR c.AnswerToQuestionRatio > 1.5)
  AND (c.BadgeScore + c.NetVotes) > 1000
GROUP BY 
    c.Id, c.DisplayName, c.Reputation, c.NetVotes, c.GoldBadges, c.SilverBadges,
    c.BronzeBadges, c.QuestionCount, c.AnswerCount, c.AnswerToQuestionRatio,
    c.BadgeScore, c.RepRank, c.LastActivity
HAVING COUNT(t.TagName) > 0

UNION ALL

SELECT 
    u.Id,
    u.DisplayName,
    u.Reputation,
    NULL,
    0,
    0,
    0,
    0,
    0,
    NULL,
    0,
    0,
    NULL,
    NULL
FROM Users u
WHERE u.Id NOT IN (SELECT Id FROM Combined)
  AND u.CreationDate > (CAST('2024-10-01' AS DATE) - INTERVAL '30 days')
ORDER BY RepRank ASC
LIMIT 100;