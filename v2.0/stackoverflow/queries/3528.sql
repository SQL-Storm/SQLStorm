-- {"query": "3528.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2303} 
WITH UserBadgeAgg AS (
    SELECT 
        b.UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END)          AS GoldCount,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END)          AS SilverCount,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END)          AS BronzeCount,
        COUNT(*)                                            AS TotalBadges
    FROM Badges b
    GROUP BY b.UserId
),
UserPostStats AS (
    SELECT 
        p.OwnerUserId                                 AS UserId,
        COUNT(*) FILTER (WHERE p.PostTypeId = 1)      AS QuestionCount,
        COUNT(*) FILTER (WHERE p.PostTypeId = 2)      AS AnswerCount,
        AVG(p.Score) FILTER (WHERE p.PostTypeId = 1)  AS AvgQuestionScore,
        AVG(p.Score) FILTER (WHERE p.PostTypeId = 2)  AS AvgAnswerScore,
        MAX(p.CreationDate)                          AS LastPostDate
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
UserVoteMetrics AS (
    SELECT 
        v.UserId,
        COUNT(*) FILTER (WHERE vt.Name = 'UpMod')                     AS UpVotesGiven,
        COUNT(*) FILTER (WHERE vt.Name = 'DownMod')                   AS DownVotesGiven,
        SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE -1 END)           AS NetVoteImpact
    FROM Votes v
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    GROUP BY v.UserId
),
RecentUserPosts AS (
    SELECT 
        p.OwnerUserId,
        p.Id                                      AS PostId,
        p.Title,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    WHERE p.Title IS NOT NULL
)
SELECT 
    u.Id                                         AS UserId,
    COALESCE(u.DisplayName, 'Anonymous')         AS DisplayName,
    u.Reputation,
    COALESCE(uba.GoldCount,0)                    AS GoldBadges,
    COALESCE(uba.SilverCount,0)                  AS SilverBadges,
    COALESCE(uba.BronzeCount,0)                  AS BronzeBadges,
    COALESCE(ups.QuestionCount,0)                AS QuestionsPosted,
    COALESCE(ups.AnswerCount,0)                  AS AnswersPosted,
    ROUND(COALESCE(ups.AvgQuestionScore,0),2)    AS AvgQScore,
    ROUND(COALESCE(ups.AvgAnswerScore,0),2)      AS AvgAScore,
    COALESCE(uvm.UpVotesGiven,0)                 AS UpVotesGiven,
    COALESCE(uvm.DownVotesGiven,0)               AS DownVotesGiven,
    COALESCE(uvm.NetVoteImpact,0)                AS NetVoteImpact,
    rp.Title                                     AS MostRecentPostTitle,
    rp.PostId                                    AS MostRecentPostId,
    CASE 
        WHEN u.Location IS NULL THEN 'UNKNOWN' 
        ELSE u.Location 
    END                                          AS LocationFlag,
    CASE 
        WHEN EXISTS (
            SELECT 1 
            FROM Posts p2 
            WHERE p2.OwnerUserId = u.Id 
              AND p2.Tags IS NOT NULL 
              AND p2.Tags LIKE '%<sql>%'
        ) THEN 1 
        ELSE 0 
    END                                          AS HasSQLTagPosts,
    (SELECT COUNT(DISTINCT ph.Id)
     FROM PostHistory ph
     WHERE ph.UserId = u.Id
       AND ph.PostHistoryTypeId = 10
       AND ph.CreationDate > DATE '2023-01-01') AS RecentCloseVotes
FROM Users u
LEFT JOIN UserBadgeAgg   uba ON uba.UserId = u.Id
LEFT JOIN UserPostStats  ups ON ups.UserId = u.Id
LEFT JOIN UserVoteMetrics uvm ON uvm.UserId = u.Id
LEFT JOIN (
    SELECT OwnerUserId, Title, PostId
    FROM RecentUserPosts
    WHERE rn = 1
) rp ON rp.OwnerUserId = u.Id
WHERE u.Reputation > 1000
  AND (u.CreationDate < cast('2024-10-01' as date) - INTERVAL '5 years' OR u.UpVotes > 0)

UNION ALL

SELECT 
    -1                                         AS UserId,
    'GhostUser'                                AS DisplayName,
    0                                          AS Reputation,
    0,0,0,
    0,0,
    0,0,
    0,0,0,
    NULL,NULL,
    'N/A'                                      AS LocationFlag,
    0                                          AS HasSQLTagPosts,
    0                                          AS RecentCloseVotes
FROM (SELECT 1) dummy
ORDER BY Reputation DESC NULLS LAST
LIMIT 100;