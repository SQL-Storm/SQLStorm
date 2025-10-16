-- {"query": "1258.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.2, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1519} 

WITH QualifiedUsers AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        COALESCE(u.Location, 'Unknown') AS Location,
        u.UpVotes,
        u.DownVotes,
        u.Views,
        RANK() OVER (ORDER BY u.Reputation DESC) AS ReputationRank,
        COUNT(b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id 
    WHERE u.Views IS NOT NULL AND u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location, u.UpVotes, u.DownVotes, u.Views
),
UserPosts AS (
    SELECT
        p.OwnerUserId AS UserId,
        p.PostTypeId,
        COUNT(*) AS PostCount,
        AVG(p.Score) AS AvgScore,
        MAX(p.ViewCount) AS MaxViews,
        COUNT(*) FILTER (WHERE p.AcceptedAnswerId IS NOT NULL) AS AcceptedAnswers,
        COUNT(DISTINCT pl.RelatedPostId) AS LinkedPostsCount
    FROM Posts p
    LEFT JOIN PostLinks pl ON pl.PostId = p.Id AND pl.LinkTypeId = 1
    WHERE p.OwnerUserId IS NOT NULL AND p.OwnerUserId != -1
    GROUP BY p.OwnerUserId, p.PostTypeId
),
UserPostSummary AS (
    SELECT
        u.Id AS UserId,
        COALESCE(SUM(CASE WHEN up.PostTypeId = 1 THEN up.PostCount ELSE 0 END), 0) AS Questions,
        COALESCE(SUM(CASE WHEN up.PostTypeId = 2 THEN up.PostCount ELSE 0 END), 0) AS Answers,
        COALESCE(SUM(CASE WHEN up.PostTypeId = 1 THEN up.AcceptedAnswers ELSE 0 END), 0) AS AcceptedAnswersGiven,
        COALESCE(SUM(CASE WHEN up.PostTypeId = 2 THEN up.AcceptedAnswers ELSE 0 END), 0) AS AcceptedAnswersReceived,
        COALESCE(SUM(COALESCE(up.AvgScore, 0) * up.PostCount),0) / NULLIF(COALESCE(SUM(up.PostCount),0),0) AS WeightedAvgScore,
        COALESCE(SUM(up.LinkedPostsCount),0) AS TotalLinkedPosts
    FROM QualifiedUsers u
    LEFT JOIN UserPosts up ON up.UserId = u.Id
    GROUP BY u.Id
),
TopTagWins AS (
    SELECT
        t.Id AS TagId,
        t.TagName,
        p.OwnerUserId,
        COUNT(*) AS PostsCount,
        RANK() OVER (PARTITION BY t.Id ORDER BY COUNT(*) DESC) AS RankInTag
    FROM Tags t
    JOIN Posts p ON p.Tags LIKE CONCAT('%<', t.TagName, '>%') AND p.OwnerUserId IS NOT NULL AND p.OwnerUserId != -1
    WHERE p.PostTypeId = 1
    GROUP BY t.Id, t.TagName, p.OwnerUserId
    HAVING COUNT(*) >= 5
),
TopUsersByTag AS (
    SELECT DISTINCT 
        o.OwnerUserId AS UserId,
        COUNT(*) OVER(PARTITION BY o.OwnerUserId) AS TagsTopCount
    FROM TopTagWins o
    WHERE o.RankInTag = 1
),
UserActivityIntervals AS (
    SELECT
        ph.UserId,
        ph.PostId,
        ph.PostHistoryTypeId,
        ph.CreationDate,
        LAG(ph.CreationDate) OVER (PARTITION BY ph.UserId ORDER BY ph.CreationDate) AS PrevEdit,
        LEAD(ph.CreationDate) OVER (PARTITION BY ph.UserId ORDER BY ph.CreationDate) AS NextEdit,
        ph.Comment
    FROM PostHistory ph
    WHERE ph.UserId IS NOT NULL
),
UserEditDurations AS (
    SELECT
        uai.UserId,
        EXTRACT(EPOCH FROM (COALESCE(uai.NextEdit, CURRENT_TIMESTAMP) - uai.CreationDate))/3600.0 AS HoursUntilNextEdit,
        uai.PostHistoryTypeId,
        uai.Comment
    FROM UserActivityIntervals uai
),
ExtremeEditDelays AS (
    SELECT
        uid.UserId,
        MAX(uid.HoursUntilNextEdit) AS MaxEditDelayHours,
        AVG(uid.HoursUntilNextEdit) AS AvgEditDelayHours
    FROM UserEditDurations uid
    GROUP BY uid.UserId
)
SELECT 
    qu.Id AS UserId,
    qu.DisplayName,
    qu.Location,
    qu.Reputation,
    qu.ReputationRank,
    qu.GoldBadges,
    qu.SilverBadges,
    qu.BronzeBadges,
    ups.Questions,
    ups.Answers,
    ups.AcceptedAnswersGiven,
    ups.AcceptedAnswersReceived,
    ROUND(ups.WeightedAvgScore,2) AS WeightedAvgScore,
    ups.TotalLinkedPosts,
    COALESCE(tut.TagsTopCount, 0) AS TagsTopContributorCount,
    COALESCE(eed.MaxEditDelayHours, 0) AS LongestHoursBetweenEdits,
    COALESCE(eed.AvgEditDelayHours, 0) AS AvgHoursBetweenEdits,
    CAST(
      CONCAT(
        COALESCE(qu.Location, 'NoLoc'), ' | ', 
        COALESCE(ups.Questions, 0), ' Qs | ',
        COALESCE(ups.Answers,0), ' As | ',
        COALESCE(qu.Views,0), ' Views | ',
        COALESCE(qu.UpVotes,0) - COALESCE(qu.DownVotes,0), ' NetVotes'
      ) AS VARCHAR(255)
    ) AS SummaryInfo
FROM QualifiedUsers qu
LEFT JOIN UserPostSummary ups ON ups.UserId = qu.Id
LEFT JOIN TopUsersByTag tut ON tut.UserId = qu.Id
LEFT JOIN ExtremeEditDelays eed ON eed.UserId = qu.Id
WHERE qu.Location IS NOT NULL
  AND (ups.Questions + ups.Answers) > 20
  AND qu.ReputationRank <= 500
ORDER BY qu.Reputation DESC, ups.WeightedAvgScore DESC
LIMIT 100
UNION
-- Additional union ALL for some complex filtered comments stats per user to test reads and aggregation
SELECT DISTINCT
    c.UserId,
    u.DisplayName,
    u.Location,
    u.Reputation,
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
    CAST('Commenter aggregate placeholder' AS VARCHAR(255))
FROM Comments c
INNER JOIN Users u ON u.Id = c.UserId
WHERE c.CreationDate > current_date - INTERVAL '180 days'
AND c.Text ~* 'bug|error|fail|exception|crash'
LIMIT 10;
