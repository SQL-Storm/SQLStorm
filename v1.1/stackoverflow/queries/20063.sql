-- {"query": "20063.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1130} 
WITH UserActivitySummary AS (
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        SUM(p.Score) AS TotalScore,
        SUM(p.ViewCount) AS TotalViewCount,
        SUM(p.FavoriteCount) AS TotalFavorites,
        MIN(p.CreationDate) AS FirstPostDate,
        MAX(p.LastActivityDate) AS LastActivityDate
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
    HAVING COUNT(p.Id) > 10
),
UserEngagementMetrics AS (
    SELECT
        c.UserId,
        COUNT(c.Id) AS CommentCount,
        SUM(c.Score) AS TotalCommentScore,
        (SELECT COUNT(*) FROM PostHistory ph WHERE ph.UserId = c.UserId AND ph.PostHistoryTypeId IN (4, 5, 6)) AS EditCount
    FROM Comments c
    WHERE c.UserId IS NOT NULL
    GROUP BY c.UserId
),
RankedUsers AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.Location,
        u.CreationDate,
        u.LastAccessDate,
        uas.TotalPosts,
        uas.QuestionCount,
        uas.AnswerCount,
        uas.TotalScore,
        uas.TotalViewCount,
        uas.TotalFavorites,
        uem.CommentCount,
        uem.EditCount,
        uas.LastActivityDate,
        ROW_NUMBER() OVER(ORDER BY u.Reputation DESC) AS OverallRank,
        NTILE(100) OVER(ORDER BY uas.TotalScore DESC) AS ScorePercentile,
        AVG(uas.TotalScore) OVER (PARTITION BY SUBSTRING(u.Location FROM POSITION(',' IN u.Location) + 2)) AS AvgScoreInCountry,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges
    FROM Users u
    JOIN UserActivitySummary uas ON u.Id = uas.UserId
    LEFT JOIN UserEngagementMetrics uem ON u.Id = uem.UserId
    WHERE u.Reputation > 5000 AND u.Location IS NOT NULL AND u.Location LIKE '%, %'
)
SELECT
    ru.DisplayName,
    ru.Reputation,
    ru.OverallRank,
    ru.Location,
    ru.TotalPosts,
    ru.AnswerCount,
    (ru.AnswerCount * 100.0 / NULLIF(ru.TotalPosts, 0)) AS AnswerRatio,
    ru.TotalScore,
    ru.ScorePercentile,
    ru.TotalViewCount,
    ru.CommentCount,
    ru.EditCount,
    ru.GoldBadges,
    EXTRACT(YEAR FROM AGE(ru.LastAccessDate, ru.CreationDate)) AS MembershipYears,
    CASE
        WHEN ru.Reputation > 100000 THEN 'Diamond Member'
        WHEN ru.Reputation > 50000 THEN 'Platinum Member'
        WHEN ru.Reputation > 10000 THEN 'Gold Member'
        ELSE 'Silver Member'
    END AS UserTier,
    (SELECT STRING_AGG(DISTINCT T.TagName, ', ' ORDER BY T.TagName)
     FROM Posts P_Tags
     JOIN Tags T ON T.Id IN (
         SELECT CAST(s.tagid AS INTEGER)
         FROM UNNEST(STRING_TO_ARRAY(SUBSTRING(P_Tags.Tags, 2, LENGTH(P_Tags.Tags) - 2), '><')) AS s(tagid)
     )
     WHERE P_Tags.OwnerUserId = ru.Id AND P_Tags.PostTypeId = 1
    ) AS TopTags,
    ru.TotalScore - ru.AvgScoreInCountry AS ScoreVsCountryAvg,
    LAG(ru.DisplayName, 1, 'N/A') OVER (PARTITION BY SUBSTRING(ru.Location FROM POSITION(',' IN ru.Location) + 2) ORDER BY ru.Reputation DESC) AS NextHighestUserInCountry
FROM RankedUsers ru
WHERE ru.GoldBadges > 0 AND EXISTS (
    SELECT 1
    FROM Posts p_sub
    WHERE p_sub.OwnerUserId = ru.Id
      AND p_sub.PostTypeId = 2 -- Is an answer
      AND p_sub.Id IN (SELECT q.AcceptedAnswerId FROM Posts q WHERE q.AcceptedAnswerId IS NOT NULL)
      AND p_sub.Score > 50
)
ORDER BY ru.Location, ru.Reputation DESC
LIMIT 500;