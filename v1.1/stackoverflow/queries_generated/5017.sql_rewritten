-- {"query": "5017.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 920} 
WITH RecentActiveUsers AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        COALESCE(MAX(p.CreationDate), u.LastAccessDate) AS LatestPostDate,
        DENSE_RANK() OVER (ORDER BY COALESCE(MAX(p.CreationDate), u.LastAccessDate) DESC) AS ActivityRank
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    WHERE u.CreationDate > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '2 years'
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
), 
UserTagStats AS (
    SELECT
        p.OwnerUserId AS UserId,
        TRIM(BOTH '<>' FROM UNNEST(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><'))) AS TagName,
        COUNT(*) AS TagPostCount,
        SUM(p.Score) AS TagScoreSum
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.CreationDate > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '2 years'
      AND p.Tags IS NOT NULL
    GROUP BY p.OwnerUserId, TagName
),
TopTagsPerUser AS (
    SELECT 
        uts.UserId,
        uts.TagName,
        uts.TagPostCount,
        uts.TagScoreSum,
        RANK() OVER (PARTITION BY uts.UserId ORDER BY uts.TagScoreSum DESC, uts.TagPostCount DESC) AS TagRank
    FROM UserTagStats uts
)
SELECT
    rau.UserId,
    rau.DisplayName,
    rau.Reputation,
    DATE_PART('day', cast('2024-10-01 12:34:56' as timestamp) - rau.CreationDate) AS DaysSinceJoined,
    DATE_PART('hour', cast('2024-10-01 12:34:56' as timestamp) - rau.LatestPostDate) AS HoursSinceLastPost,
    COALESCE(b.BadgeCount, 0) AS TotalBadges,
    COALESCE(pq.PostCount, 0) AS QuestionsPosted,
    COALESCE(pa.PostCount, 0) AS AnswersPosted,
    tt.TagName AS TopTag,
    tt.TagPostCount AS TopTagPosts,
    tt.TagScoreSum AS TopTagScore,
    CASE 
        WHEN rau.Reputation > 10000 THEN 'Legend'
        WHEN rau.Reputation BETWEEN 1001 AND 10000 THEN 'Pro'
        ELSE 'Rookie'
    END AS UserTier,
    CASE 
        WHEN pa.PostCount = 0 THEN NULL 
        ELSE ROUND(CAST(pa.PostScoreSum AS NUMERIC)/pa.PostCount,2)
    END AS AvgAnswerScore,
    (SELECT COUNT(*) 
     FROM Votes v 
     WHERE v.UserId = rau.UserId 
       AND v.VoteTypeId = 2) AS UpVotesCast,
    (
        SELECT COUNT(*)
        FROM Badges b2
        WHERE b2.UserId = rau.UserId AND b2.Class = 1
    ) AS GoldBadges,
    (
        SELECT COUNT(*)
        FROM Comments c
        WHERE c.UserId = rau.UserId 
          AND c.Score > 5
    ) AS HighlyVotedComments
FROM RecentActiveUsers rau
LEFT JOIN (
    SELECT b.UserId, COUNT(*) AS BadgeCount
    FROM Badges b
    WHERE b.Date > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '2 years'
    GROUP BY b.UserId
) b ON b.UserId = rau.UserId
LEFT JOIN (
    SELECT p.OwnerUserId, COUNT(*) AS PostCount
    FROM Posts p
    WHERE p.PostTypeId = 1
    GROUP BY p.OwnerUserId
) pq ON pq.OwnerUserId = rau.UserId
LEFT JOIN (
    SELECT p.OwnerUserId, COUNT(*) AS PostCount, SUM(p.Score) AS PostScoreSum
    FROM Posts p
    WHERE p.PostTypeId = 2
    GROUP BY p.OwnerUserId
) pa ON pa.OwnerUserId = rau.UserId
LEFT JOIN (
    SELECT ttpu.UserId, ttpu.TagName, ttpu.TagPostCount, ttpu.TagScoreSum
    FROM TopTagsPerUser ttpu
    WHERE ttpu.TagRank = 1
) tt ON tt.UserId = rau.UserId
WHERE rau.ActivityRank <= 100
ORDER BY rau.ActivityRank
;