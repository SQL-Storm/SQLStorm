WITH UserActivity AS (
    SELECT 
        u.Id AS UserId,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        AVG(p.Score) AS AvgPostScore,
        MAX(u.Reputation) AS MaxReputation,
        STRING_AGG(DISTINCT b.Name, ', ') AS BadgeNames
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.LastAccessDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 YEAR'
        AND (u.Views > 1000 OR u.UpVotes > 50)
    GROUP BY u.Id
),
PostFeedback AS (
    SELECT 
        p.Id AS PostId,
        p.OwnerUserId,
        COUNT(c.Id) AS CommentCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
        p.Score,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS PostRank
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE p.CreationDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '2 YEARS'
        AND (p.ViewCount > 500 OR p.Score > 10)
    GROUP BY p.Id, p.OwnerUserId, p.Score
),
TopUserPerformance AS (
    SELECT 
        ua.UserId,
        ua.QuestionCount,
        ua.AnswerCount,
        ua.AvgPostScore,
        pf.CommentCount,
        pf.UpVoteCount,
        pf.DownVoteCount,
        RANK() OVER (ORDER BY ua.MaxReputation DESC, pf.CommentCount DESC) AS UserRank
    FROM UserActivity ua
    INNER JOIN PostFeedback pf ON ua.UserId = pf.OwnerUserId
    WHERE pf.PostRank <= 5
)
SELECT 
    tup.UserId,
    u.DisplayName,
    tup.QuestionCount,
    tup.AnswerCount,
    tup.AvgPostScore,
    tup.CommentCount,
    tup.UpVoteCount,
    tup.DownVoteCount,
    tup.UserRank,
    COALESCE(u.AboutMe, 'No about me info') AS UserBio
FROM TopUserPerformance tup
JOIN Users u ON tup.UserId = u.Id
WHERE tup.UserRank <= 10
ORDER BY tup.UserRank;