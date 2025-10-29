-- {"query": "3185.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2137} 

WITH UserStats AS (
    SELECT 
        u.Id                     AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        SUM(COALESCE(p.Score,0)) AS TotalScore,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY u.Reputation DESC) AS rn
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
TagUsage AS (
    SELECT 
        t.Id        AS TagId,
        t.TagName,
        COUNT(*)    AS TagPostCount,
        ROW_NUMBER() OVER (ORDER BY COUNT(*) DESC) AS TagRank
    FROM Tags t
    JOIN Posts p ON p.Tags LIKE ('%<'||t.TagName||'>%')
    WHERE p.PostTypeId = 1
    GROUP BY t.Id, t.TagName
),
TopUserTags AS (
    SELECT 
        us.UserId,
        tu.TagName,
        COUNT(*)                         AS UserTagCount,
        ROW_NUMBER() OVER (PARTITION BY us.UserId ORDER BY COUNT(*) DESC) AS TagSeq
    FROM UserStats us
    JOIN Posts p   ON p.OwnerUserId = us.UserId
    JOIN Tags t    ON p.Tags LIKE ('%<'||t.TagName||'>%')
    JOIN TagUsage tu ON tu.TagId = t.Id
    WHERE us.rn = 1
    GROUP BY us.UserId, tu.TagName
),
RecentVotes AS (
    SELECT 
        v.PostId,
        MAX(v.CreationDate)                                          AS LastVoteDate,
        SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END)           AS UpVotes,
        SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END)         AS DownVotes
    FROM Votes v
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    WHERE v.CreationDate >= CURRENT_DATE - INTERVAL '30 days'
    GROUP BY v.PostId
)
SELECT 
    us.UserId,
    us.DisplayName,
    us.Reputation,
    us.QuestionCount,
    us.AnswerCount,
    us.TotalScore,
    COALESCE(rv.UpVotes,0)      AS RecentUpVotes,
    COALESCE(rv.DownVotes,0)    AS RecentDownVotes,
    tu.TagName,
    tu.UserTagCount,
    CASE 
        WHEN us.Reputation > 20000 THEN 'Legend'
        WHEN us.Reputation > 10000 THEN 'Expert'
        WHEN us.Reputation > 1000  THEN 'Experienced'
        ELSE 'Newbie' 
    END                        AS ReputationBand,
    CASE 
        WHEN EXISTS (SELECT 1 FROM Badges b WHERE b.UserId = us.UserId AND b.Class = 1) THEN 1
        ELSE 0 
    END                        AS HasGoldBadge,
    COALESCE(p.Title, '[No Title]') AS LatestPostTitle,
    ROW_NUMBER() OVER (PARTITION BY us.UserId ORDER BY p.CreationDate DESC) AS RecentPostSeq
FROM UserStats us
LEFT JOIN TopUserTags tu 
       ON tu.UserId = us.UserId AND tu.TagSeq = 1
LEFT JOIN Posts p 
       ON p.OwnerUserId = us.UserId 
      AND p.CreationDate = (
            SELECT MAX(p2.CreationDate) 
            FROM Posts p2 
            WHERE p2.OwnerUserId = us.UserId
        )
LEFT JOIN RecentVotes rv 
       ON rv.PostId = p.Id
WHERE us.rn = 1

UNION ALL

SELECT 
    NULL                AS UserId,
    'Aggregate'         AS DisplayName,
    NULL                AS Reputation,
    SUM(us.QuestionCount) AS QuestionCount,
    SUM(us.AnswerCount)   AS AnswerCount,
    SUM(us.TotalScore)    AS TotalScore,
    SUM(COALESCE(rv.UpVotes,0))   AS RecentUpVotes,
    SUM(COALESCE(rv.DownVotes,0)) AS RecentDownVotes,
    NULL                AS TagName,
    NULL                AS UserTagCount,
    'Overall'           AS ReputationBand,
    NULL                AS HasGoldBadge,
    NULL                AS LatestPostTitle,
    NULL                AS RecentPostSeq
FROM UserStats us
LEFT JOIN RecentVotes rv 
       ON rv.PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = us.UserId)
WHERE us.rn = 1

ORDER BY Reputation DESC NULLS LAST
LIMIT 100;
