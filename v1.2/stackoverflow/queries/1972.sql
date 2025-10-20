WITH RecentUserActivityRanked AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        u.UpVotes,
        u.DownVotes,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) AS NumberofQuestions,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) AS NumberofAnswers,
        COUNT(DISTINCT b.Id) AS BadgesEarned,
        DENSE_RANK() OVER (PARTITION BY CAST(u.CreationDate AS DATE) ORDER BY u.Reputation DESC) AS DailyRepopularityRank,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS OverallEnhRepLbRank
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        u.UpVotes,
        u.DownVotes
)
SELECT *
FROM RecentUserActivityRanked;