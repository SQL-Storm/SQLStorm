WITH UserPostStats AS (
    SELECT 
        u.Id,
        u.DisplayName,
        COUNT(p.Id) AS TotalPosts,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) AS QuestionCount,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) AS AnswerCount,
        AVG(p.Score) AS AvgPostScore,
        SUM(p.ViewCount) AS TotalViews,
        STRING_AGG(DISTINCT t.TagName, ', ') AS TopTags
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN (
        SELECT p.Id AS PostId,
               TRIM(tag) AS TagName
        FROM Posts p,
             LATERAL (
               SELECT UNNEST(string_to_array(substring(p.Tags FROM 2 FOR (length(p.Tags) - 2)), '><')) AS tag
             ) s
        WHERE p.Tags IS NOT NULL AND p.PostTypeId = 1
    ) t ON p.Id = t.PostId
    GROUP BY u.Id, u.DisplayName
),
UserBadgeStats AS (
    SELECT 
        u.Id,
        COUNT(b.Id) AS TotalBadges,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
        MAX(b.Date) AS LastBadgeDate
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id
),
UserVoteStats AS (
    SELECT 
        u.Id,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpVotesReceived,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownVotesReceived,
        SUM(CASE WHEN v.VoteTypeId = 9 THEN v.BountyAmount ELSE 0 END) AS BountyReceived,
        AVG((EXTRACT(EPOCH FROM v.CreationDate) - EXTRACT(EPOCH FROM u.CreationDate)) / 86400.0) AS AvgVoteAgeDays
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Votes v ON p.Id = v.PostId
    GROUP BY u.Id, u.CreationDate
),
RankedUsers AS (
    SELECT 
        COALESCE(ups.Id, ubs.Id, uvs.Id) AS Id,
        COALESCE(ups.DisplayName, CAST(COALESCE(ubs.Id, uvs.Id) AS VARCHAR)) AS DisplayName,
        COALESCE(ups.TotalPosts, 0) + COALESCE(ubs.TotalBadges, 0) + COALESCE(uvs.UpVotesReceived, 0) AS ActivityScore,
        ROW_NUMBER() OVER (ORDER BY COALESCE(ups.TotalPosts, 0) + COALESCE(ubs.TotalBadges, 0) + COALESCE(uvs.UpVotesReceived, 0) DESC) AS Rank,
        ups.TopTags,
        ubs.LastBadgeDate,
        uvs.AvgVoteAgeDays,
        CASE 
            WHEN COALESCE(ubs.TotalBadges,0) > 10 AND COALESCE(uvs.UpVotesReceived,0) > 1000 THEN 'Elite'
            WHEN COALESCE(ubs.TotalBadges,0) BETWEEN 5 AND 10 THEN 'Advanced'
            ELSE 'Regular'
        END AS UserTier
    FROM UserPostStats ups
    LEFT JOIN UserBadgeStats ubs ON ups.Id = ubs.Id
    LEFT JOIN UserVoteStats uvs ON COALESCE(ups.Id, ubs.Id) = uvs.Id
    JOIN Users u ON COALESCE(ups.Id, ubs.Id, uvs.Id) = u.Id
    GROUP BY 
        COALESCE(ups.Id, ubs.Id, uvs.Id),
        COALESCE(ups.DisplayName, CAST(COALESCE(ubs.Id, uvs.Id) AS VARCHAR)),
        COALESCE(ups.TotalPosts, 0) + COALESCE(ubs.TotalBadges, 0) + COALESCE(uvs.UpVotesReceived, 0),
        ups.TopTags,
        ubs.LastBadgeDate,
        uvs.AvgVoteAgeDays,
        CASE 
            WHEN COALESCE(ubs.TotalBadges,0) > 10 AND COALESCE(uvs.UpVotesReceived,0) > 1000 THEN 'Elite'
            WHEN COALESCE(ubs.TotalBadges,0) BETWEEN 5 AND 10 THEN 'Advanced'
            ELSE 'Regular'
        END
)
SELECT 
    ru.Rank,
    ru.DisplayName,
    ru.ActivityScore,
    ru.TopTags,
    ru.LastBadgeDate,
    EXTRACT(YEAR FROM (DATE_TRUNC('day', TIMESTAMP '2024-10-01 12:34:56') - DATE_TRUNC('day', ru.LastBadgeDate))) AS YearsSinceLastBadge,
    ru.AvgVoteAgeDays,
    ru.UserTier,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = ru.Id AND p.Score > 10) AS HighScorePosts,
    CASE WHEN ru.TopTags IS NULL THEN 'No Tags' ELSE substring(ru.TopTags FROM 1 FOR 50) END AS TruncatedTags,
    ru.ActivityScore / NULLIF((EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - u.CreationDate)) / 86400.0), 0) AS DailyActivityRate
FROM RankedUsers ru
JOIN Users u ON ru.Id = u.Id
WHERE ru.Rank <= 100
ORDER BY ru.ActivityScore DESC;