-- {"query": "3470.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1465} 

WITH RECURSIVE TagHierarchy AS (
    SELECT
        t.Id,
        t.TagName,
        NULL::int   AS ParentTagId,
        0          AS Depth,
        t.Count    AS TagCount
    FROM Tags t
    WHERE t.IsModeratorOnly = 0
    UNION ALL
    SELECT
        ct.Id,
        ct.TagName,
        th.Id      AS ParentTagId,
        th.Depth + 1,
        ct.Count   AS TagCount
    FROM Tags ct
    JOIN TagHierarchy th ON ct.TagName LIKE th.TagName || '-%'
    WHERE ct.IsModeratorOnly = 0
),
UserStats AS (
    SELECT
        u.Id                           AS UserId,
        u.DisplayName,
        u.Reputation,
        COALESCE(u.UpVotes,0) - COALESCE(u.DownVotes,0) AS NetVotes,
        COUNT(p.Id)                    AS TotalPosts,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) AS Questions,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) AS Answers,
        AVG(COALESCE(p.Score,0))       AS AvgPostScore,
        MAX(p.CreationDate)            AS LastPostDate,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS RepRank,
        DENSE_RANK() OVER (ORDER BY AVG(COALESCE(p.Score,0)) DESC) AS ScoreRank
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.UpVotes, u.DownVotes
),
BadgeAgg AS (
    SELECT
        b.UserId,
        STRING_AGG(DISTINCT b.Name, ', ') AS BadgeList,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldCount,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverCount,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeCount
    FROM Badges b
    GROUP BY b.UserId
),
TopTagsPerUser AS (
    SELECT
        p.OwnerUserId                              AS UserId,
        UNNEST(string_to_array(p.Tags, '><'))      AS Tag,
        COUNT(*) OVER (PARTITION BY p.OwnerUserId, UNNEST(string_to_array(p.Tags, '><'))) AS TagUsage,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY COUNT(*) OVER (PARTITION BY p.OwnerUserId, UNNEST(string_to_array(p.Tags, '><'))) DESC) AS TagRank
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
),
UserTagSummary AS (
    SELECT
        utpu.UserId,
        STRING_AGG(DISTINCT CASE WHEN utpu.TagRank = 1 THEN utpu.Tag END, ', ') AS TopTag,
        MAX(utpu.TagUsage)                                           AS TopTagUsage
    FROM TopTagsPerUser utpu
    GROUP BY utpu.UserId
),
RecentActivity AS (
    SELECT
        u.Id                     AS UserId,
        MAX(v.CreationDate)      AS LastVoteDate,
        MAX(c.CreationDate)      AS LastCommentDate,
        MAX(ph.CreationDate)     AS LastEditDate
    FROM Users u
    LEFT JOIN Votes v ON v.UserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    LEFT JOIN PostHistory ph ON ph.UserId = u.Id
    GROUP BY u.Id
),
Combined AS (
    SELECT
        us.UserId,
        us.DisplayName,
        us.Reputation,
        us.NetVotes,
        us.TotalPosts,
        us.Questions,
        us.Answers,
        ROUND(us.AvgPostScore,2)           AS AvgScore,
        us.LastPostDate,
        us.RepRank,
        us.ScoreRank,
        ba.BadgeList,
        ba.GoldCount,
        ba.SilverCount,
        ba.BronzeCount,
        uts.TopTag,
        uts.TopTagUsage,
        ra.LastVoteDate,
        ra.LastCommentDate,
        ra.LastEditDate,
        CASE 
            WHEN us.Reputation > 20000 THEN 'Legendary'
            WHEN us.Reputation > 10000 THEN 'Expert'
            WHEN us.Reputation > 5000  THEN 'Advanced'
            WHEN us.Reputation > 1000  THEN 'Intermediate'
            ELSE 'Newbie'
        END                                AS ReputationTier,
        COALESCE(us.Answers,0) * 1.0 / NULLIF(us.Questions,0) AS AnswerRate,
        (SELECT COUNT(*) 
         FROM PostLinks pl 
         WHERE pl.PostId = (SELECT Id FROM Posts p2 WHERE p2.OwnerUserId = us.UserId AND p2.PostTypeId = 1 ORDER BY p2.CreationDate DESC LIMIT 1)
           AND pl.LinkTypeId = 3)       AS DuplicateCount
    FROM UserStats us
    LEFT JOIN BadgeAgg ba       ON ba.UserId = us.UserId
    LEFT JOIN UserTagSummary uts ON uts.UserId = us.UserId
    LEFT JOIN RecentActivity ra ON ra.UserId = us.UserId
)
SELECT *
FROM Combined
WHERE ReputationTier IN ('Expert','Legendary')
   OR GoldCount >= 5
   OR DuplicateCount > 2
ORDER BY RepRank
LIMIT 100
UNION ALL
SELECT
    NULL AS UserId,
    'Aggregates' AS DisplayName,
    NULL,
    NULL,
    SUM(TotalPosts) AS TotalPosts,
    SUM(Questions)  AS Questions,
    SUM(Answers)    AS Answers,
    AVG(AvgScore)   AS AvgScore,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL
FROM Combined;
