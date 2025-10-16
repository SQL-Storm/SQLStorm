-- {"query": "20019.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1636} 

WITH UserAnswerStats AS (
    -- Calculate detailed statistics for each user's answers, including acceptance time.
    SELECT
        ans.OwnerUserId,
        COUNT(ans.Id) AS TotalAnswers,
        AVG(ans.Score) AS AverageAnswerScore,
        SUM(CASE WHEN que.AcceptedAnswerId = ans.Id THEN 1 ELSE 0 END) AS AcceptedAnswers,
        AVG(CASE WHEN que.AcceptedAnswerId = ans.Id THEN EXTRACT(EPOCH FROM (ans.CreationDate - que.CreationDate)) / 3600.0 ELSE NULL END) AS AvgHoursToAcceptance
    FROM Posts AS ans
    JOIN Posts AS que ON ans.ParentId = que.Id
    WHERE ans.PostTypeId = 2 -- Answers
      AND que.PostTypeId = 1 -- Questions
      AND ans.OwnerUserId IS NOT NULL
    GROUP BY ans.OwnerUserId
),
UserTopTag AS (
    -- Identify the primary tag for each user based on their question-posting frequency.
    SELECT
        UserId,
        TopTag,
        TagCount
    FROM (
        SELECT
            p.OwnerUserId AS UserId,
            t.TagName AS TopTag,
            COUNT(*) AS TagCount,
            ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY COUNT(*) DESC, t.TagName) AS rn
        FROM Posts p
        CROSS JOIN LATERAL unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS tag_name
        JOIN Tags t ON t.TagName = tag_name
        WHERE p.PostTypeId = 1 -- Questions
          AND p.OwnerUserId IS NOT NULL
          AND p.Tags IS NOT NULL
        GROUP BY p.OwnerUserId, t.TagName
    ) AS UserTagCounts
    WHERE rn = 1
),
UserBadgeRanks AS (
    -- Rank users based on their gold badge counts, partitioned by the first letter of their display name.
    SELECT
        UserId,
        TotalGoldBadges,
        TotalSilverBadges,
        TotalBronzeBadges,
        RANK() OVER (PARTITION BY SUBSTRING(u.DisplayName, 1, 1) ORDER BY COUNT(CASE WHEN b.Class = 1 THEN 1 END) DESC) AS GoldBadgeRankInInitial
    FROM Badges b
    JOIN Users u ON b.UserId = u.Id
    WHERE u.DisplayName IS NOT NULL AND u.DisplayName != ''
    GROUP BY b.UserId, u.DisplayName
),
QuestionAnalysis AS (
    -- Correlated subquery to find questions with scores higher than the user's average answer score.
    SELECT
        q.OwnerUserId,
        COUNT(q.Id) as HighScoringQuestions
    FROM Posts q
    WHERE q.PostTypeId = 1 -- Questions
      AND q.OwnerUserId IS NOT NULL
      AND q.Score > (
          SELECT COALESCE(AVG(p2.Score), 0)
          FROM Posts p2
          WHERE p2.PostTypeId = 2 -- Answers
            AND p2.OwnerUserId = q.OwnerUserId
      )
    GROUP BY q.OwnerUserId
)
-- Main query to synthesize all the information into a comprehensive user profile.
SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.Age,
    uas.TotalAnswers,
    uas.AverageAnswerScore,
    COALESCE(uas.AvgHoursToAcceptance, -1) AS AvgHoursToAcceptance,
    CASE
        WHEN uas.TotalAnswers > 0 THEN (uas.AcceptedAnswers::decimal / uas.TotalAnswers) * 100
        ELSE 0
    END AS AcceptanceRate,
    utt.TopTag AS PrimaryTag,
    utt.TagCount AS PrimaryTagPosts,
    ubr.TotalGoldBadges,
    ubr.TotalSilverBadges,
    ubr.GoldBadgeRankInInitial,
    qa.HighScoringQuestions,
    -- Complex scoring metric combining various user activities.
    (u.Reputation * 0.2 + uas.AverageAnswerScore * 10 + ubr.TotalGoldBadges * 100 - COALESCE(uas.AvgHoursToAcceptance, 100) * 0.5) AS EngagementScore,
    -- Lag function to compare reputation with the next user in the same location.
    u.Reputation - LAG(u.Reputation, 1, 0) OVER (PARTITION BY u.Location ORDER BY u.Reputation DESC) AS ReputationDiffVsNextInLocation,
    'High Activity User' AS UserType
FROM Users u
LEFT JOIN UserAnswerStats uas ON u.Id = uas.OwnerUserId
LEFT JOIN UserTopTag utt ON u.Id = utt.UserId
LEFT JOIN UserBadgeRanks ubr ON u.Id = ubr.UserId
LEFT JOIN QuestionAnalysis qa ON u.Id = qa.OwnerUserId
WHERE u.Reputation > 5000
  AND u.LastAccessDate > (NOW() - INTERVAL '1 year')
  AND uas.TotalAnswers > 10
  AND uas.AverageAnswerScore > 5
  AND u.Location IS NOT NULL
  AND LENGTH(u.AboutMe) > 50

UNION ALL

-- A different set of users: "Prolific Editors" who might not be high-rep posters.
SELECT
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.Age,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id),
    NULL,
    NULL,
    NULL,
    ph.LastEditTag,
    ph.TotalEdits,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1),
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2),
    NULL,
    NULL,
    (u.Reputation * 0.1 + ph.TotalEdits * 2.5),
    NULL,
    'Prolific Editor' AS UserType
FROM Users u
JOIN (
    -- Aggregate post history to find users with many edits.
    SELECT
        ph.UserId,
        COUNT(ph.Id) AS TotalEdits,
        MAX(p.Tags) AS LastEditTag -- Arbitrarily get tags from one of the edited posts
    FROM PostHistory ph
    JOIN Posts p ON ph.PostId = p.Id
    WHERE ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Body, Tags
      AND ph.UserId IS NOT NULL
      AND ph.UserId != p.OwnerUserId -- Only count edits on others' posts
    GROUP BY ph.UserId
    HAVING COUNT(ph.Id) > 200 -- Having clause to find highly active editors
) AS ph ON u.Id = ph.UserId
WHERE u.Reputation < 10000 -- Look for users who specialize in editing rather than answering.
  AND u.CreationDate < (NOW() - INTERVAL '3 year')
ORDER BY UserType, EngagementScore DESC
LIMIT 500;
