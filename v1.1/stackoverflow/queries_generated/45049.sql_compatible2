WITH RankedUserPosts AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        p.Id AS PostId,
        p.Score,
        p.CreationDate,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY p.Score DESC, p.CreationDate DESC) AS PostRank,
        COUNT(*) OVER (PARTITION BY u.Id) AS TotalUserPosts,
        p.Tags
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId = 1
      AND p.CreationDate > (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '5 years')
),
UserTagStats AS (
    SELECT 
        r.UserId,
        r.DisplayName,
        STRING_AGG(t.TagName, ',' ORDER BY r.PostRank) AS TopTags,
        MAX(r.Score) AS MaxQuestionScore,
        AVG(r.Score) AS AvgQuestionScore
    FROM RankedUserPosts r
    CROSS JOIN LATERAL (
        SELECT DISTINCT unn AS TagText
        FROM UNNEST(STRING_TO_ARRAY(SUBSTRING(r.Tags, 2, LENGTH(r.Tags) - 2), '><')) AS unn
    ) taglist
    LEFT JOIN Tags t ON t.TagName = taglist.TagText
    WHERE r.PostRank <= 5
    GROUP BY r.UserId, r.DisplayName
)
SELECT 
    uts.UserId,
    uts.DisplayName,
    uts.TopTags,
    uts.MaxQuestionScore,
    uts.AvgQuestionScore,
    COUNT(v.Id) AS TotalVotes,
    COUNT(DISTINCT b.Id) AS BadgeCount
FROM UserTagStats uts
LEFT JOIN Votes v ON v.UserId = uts.UserId
LEFT JOIN Badges b ON b.UserId = uts.UserId
WHERE uts.AvgQuestionScore > 2
GROUP BY uts.UserId, uts.DisplayName, uts.TopTags, uts.MaxQuestionScore, uts.AvgQuestionScore
ORDER BY TotalVotes DESC
LIMIT 1000;