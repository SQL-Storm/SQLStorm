-- {"query": "3668.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2342} 

WITH UserStats AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(b.GoldCnt, 0)   AS GoldBadges,
        COALESCE(b.SilverCnt, 0) AS SilverBadges,
        COALESCE(b.BronzeCnt, 0) AS BronzeBadges,
        COALESCE(v.UpCnt, 0)     AS TotalUpVotes,
        COALESCE(v.DownCnt, 0)   AS TotalDownVotes,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1) AS QuestionCount,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2) AS AnswerCount,
        (SELECT MAX(CreationDate) FROM Posts p WHERE p.OwnerUserId = u.Id)               AS LastPostDate
    FROM Users u
    LEFT JOIN (
        SELECT 
            UserId,
            SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldCnt,
            SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverCnt,
            SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeCnt
        FROM Badges
        GROUP BY UserId
    ) b ON b.UserId = u.Id
    LEFT JOIN (
        SELECT 
            UserId,
            SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpCnt,
            SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownCnt
        FROM Votes
        GROUP BY UserId
    ) v ON v.UserId = u.Id
),

RecentActivePosts AS (
    SELECT 
        p.Id,
        p.OwnerUserId,
        p.Title,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn,
        COALESCE(
            STRING_AGG(tag, ',') WITHIN GROUP (ORDER BY tag),
            ''
        ) AS TagList
    FROM Posts p
    LEFT JOIN LATERAL (
        SELECT TRIM(BOTH '<>' FROM regexp_split_to_table(p.Tags, '><')) AS tag
    ) t(tag) ON true
    WHERE p.PostTypeId = 1                      -- only questions
    GROUP BY p.Id, p.OwnerUserId, p.Title, p.CreationDate
),

UserRankings AS (
    SELECT
        us.Id,
        us.DisplayName,
        us.Reputation,
        us.GoldBadges,
        us.SilverBadges,
        us.BronzeBadges,
        us.TotalUpVotes,
        us.TotalDownVotes,
        us.QuestionCount,
        us.AnswerCount,
        us.LastPostDate,
        RANK() OVER (
            ORDER BY 
                us.Reputation DESC,
                us.GoldBadges DESC,
                us.SilverBadges DESC,
                us.TotalUpVotes DESC
        ) AS RepRank
    FROM UserStats us
)

SELECT 
    ur.Id,
    ur.DisplayName,
    ur.Reputation,
    ur.GoldBadges,
    ur.SilverBadges,
    ur.BronzeBadges,
    ur.TotalUpVotes,
    ur.TotalDownVotes,
    ur.QuestionCount,
    ur.AnswerCount,
    ur.RepRank,
    COALESCE(rp.Title, '(no recent question)')      AS RecentQuestionTitle,
    CASE 
        WHEN ur.LastPostDate IS NULL THEN 'Never posted' 
        ELSE to_char(ur.LastPostDate, 'YYYY-MM-DD') 
    END                                            AS LastPostDate,
    CASE 
        WHEN ur.QuestionCount = 0 THEN NULL 
        ELSE (ur.AnswerCount::float / NULLIF(ur.QuestionCount,0)) 
    END                                            AS AnswersPerQuestion,
    CASE 
        WHEN ur.TotalDownVotes = 0 THEN 0 
        ELSE (ur.TotalUpVotes::float / ur.TotalDownVotes) 
    END                                            AS UpDownRatio,
    CASE 
        WHEN ur.RepRank <= 10  THEN 'Top 10' 
        WHEN ur.RepRank <= 100 THEN 'Top 100' 
        ELSE 'Other' 
    END                                            AS Tier
FROM UserRankings ur
LEFT JOIN (
    SELECT rap.OwnerUserId, rap.Title
    FROM RecentActivePosts rap
    WHERE rap.rn = 1
) rp ON rp.OwnerUserId = ur.Id
WHERE ur.Reputation > 1000

UNION ALL

SELECT 
    -1                                 AS Id,
    'Anonymous'                        AS DisplayName,
    0                                  AS Reputation,
    0                                  AS GoldBadges,
    0                                  AS SilverBadges,
    0                                  AS BronzeBadges,
    0                                  AS TotalUpVotes,
    0                                  AS TotalDownVotes,
    0                                  AS QuestionCount,
    0                                  AS AnswerCount,
    NULL                               AS RepRank,
    NULL                               AS RecentQuestionTitle,
    NULL                               AS LastPostDate,
    NULL                               AS AnswersPerQuestion,
    NULL                               AS UpDownRatio,
    'Other'                            AS Tier
WHERE NOT EXISTS (SELECT 1 FROM Users WHERE Reputation > 1000);
